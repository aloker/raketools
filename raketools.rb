require 'configatron'
require 'rake/clean'
require 'rexml/document'
require 'rexml/xpath'


CLEAN.clear if defined? CLEAN and CLEAN.respond_to? :clear
CLOBBER.clear if defined? CLOBBER and CLOBBER.respond_to? :clear

task :clean => [:init]

task :clobber => [:init] do
  sleep(0.2)
end

task :init do
  Raketools.init() 
end

module Raketools
  attr_reader :configured  # true if configure has been called
  attr_reader :initialized # true if init has been called
  attr :project_info

  def Raketools.configure(environment = nil)
    return if @configured
    
    environment = ENV.fetch('RT_ENVIRONMENT', nil) if environment.nil?
    
    defaults = \
    { :product => { :version     => '1.0.0.$(ENV:BUILD_NUMBER)',
                    :assemblyversion      => '$(VER:ALL)',
                    :fileversion          => '$(VER:ALL)',
                    :informationalversion => '$(VER:ALL)'},
      :dir     => { :output     => 'build',
                    :build      => '$(output)/bin', 
                    :source     => 'source', 
                    :reports    => '$(output)/reports', 
                    :tools      => 'tools'},
      :build   => { :config     => 'Debug',
                    :verbose    => false,
                    :keyfile    => nil,
                    :delaysign  => false},
	  :generate =>{ :versioninfohead => ''},
      :test    => { :coverage   => true, 
                    :enabled    => true },
      :tool    => { :nunit      => '$(tools)/nunit/bin/net-2.0/nunit-console-x86.exe',
                    :ncover     => '$(tools)/ncover/ncover.console.exe',
                    :stylecop   => '$(tools)/stylecopcmd/stylecopcmd.exe',
                    :gendarme   => '$(tools)/gendarme/gendarme.exe',
                    :simian     => '$(tools)/simian/bin/simian.exe',
                    :fxcop      => '$(tools)/fxcop/FxCopCmd.exe',
                    :ilmerge    => '$(tools)/ilmerge/ILMerge.exe',
					:partcover  => '$(tools)/partcover4/PartCover.exe'},
      :analysis => {:enabled    => true },
      :gendarme => {:ignorefile => 'Gendarme.ignore' }    
    }    
    
    configatron.configure_from_hash(defaults)        
    load_config(ENV.fetch('RT_PROJECTCONFIG', 'raketools-config.yml'), environment)
    load_config(ENV.fetch('RT_LOCALCONFIG', 'local-config.yml'), environment)    	
    sync_config_with_env(configatron)    
    resolve_version()            
    resolve_variables()  
    log(__method__, "Active configuration")
    configatron.inspect.each_line do |x| 
        puts " * #{x["configatron.".length..-1]}"
    end   
    
    CLOBBER << configatron.dir.output
    
    @configured = true
  end
  
  def Raketools.load_config(filename, environment)
    if File.exists?(filename)
      configatron.configure_from_yaml(filename, :hash => 'common') 
      configatron.configure_from_yaml(filename, :hash => environment) if !environment.nil?
    end
  end
  
  def Raketools.resolve_variables()
    configatron.dir.build = File.join(configatron.dir.output, configatron.dir.build.sub(/^\$\(output\)/, '')) if configatron.dir.build.match(/^\$\(output\)/)
    configatron.dir.reports = File.join(configatron.dir.output, configatron.dir.reports.sub(/^\$\(output\)/, '')) if configatron.dir.reports.match(/^\$\(output\)/)
    toolhash = configatron.tool.to_hash
    toolhash.each do |k,v| 
	  configatron.tool.send("#{k}=", File.join(configatron.dir.tools, toolhash[k].sub(/^\$\(tools\)/, ''))) if  toolhash[k].match(/^\$\(tools\)/)
    end
  end
 
  def Raketools.sync_config_with_env(cfg)
    hash = cfg.to_hash
	sync_config_with_env_vars(hash, "")
	cfg.configure_from_hash(hash)
  end
  
  def Raketools.sync_config_with_env_vars(hash, hierarchy)
    hash.each do |k,v|		
		if v.kind_of? Hash			
			hier = hierarchy
			hier = hier + "_" if hier.length > 0			
			sync_config_with_env_vars(v, hier + k.to_s)
		else			
			hier = hierarchy.upcase
			hier = hier + "_" if hier.length > 0
			key = "RT_#{hier}#{k.upcase}".gsub(/\./, '_')        			
			value = ENV.fetch(key, nil)
			if not value.nil?
			  if v.kind_of? TrueClass or v.kind_of? FalseClass 
				value = value.to_b
			  end
			  log(__method__, "Overriding #{hierarchy}.#{k}")
			  hash[k] = value
			end
		end			
    end
  end  
  
  def Raketools.quick
    configatron.test.enabled = false
    configatron.analysis.enabled = false
  end  
  
  def Raketools.build_config(which)
    configatron.build.config = which
  end
  
  def Raketools.resolve_version()   
    configatron.product.version = parse_numeric_version()
    # build derived versions
    configatron.product.assemblyversion = build_version(configatron.product.assemblyversion)
    configatron.product.fileversion = build_version(configatron.product.fileversion )
    configatron.product.informationalversion = build_version(configatron.product.informationalversion)
  end
  
  def Raketools.build_version(version,allow_version_prefix=true)
    version = version.to_s
    
    version.gsub!( /\$\(([^:]+):([^\)]+)\)/) do |m|      
      key = $1
      value = $2
      result = ''      
      case key
        when 'ENV'
          result = ENV.fetch(value, '')
        when 'GIT'
          case value          
            when 'COMMITS'
              result = git_commit_count_in_branch()
            when 'BRANCH'
              result = git_current_branch()
            when 'HASH'
              result = git_current_commit_hash(false)
            when 'SHORTHASH'
              result = git_current_commit_hash(true)
            when 'DESCRIBE-VERSION-1'
              result = git_describe_version(1).join('.')
            when 'DESCRIBE-VERSION-2'
              result = git_describe_version(2).join('.')
            when 'DESCRIBE-VERSION-3'
              result = git_describe_version(3).join('.')
            when 'DESCRIBE-VERSION-4'
              result = git_describe_version(4).join('.')
            when 'DESCRIBE-COMMITS'
              result = git_describe_commits()
          end
        when 'VER'
          if not allow_version_prefix
            raise 'VER prefix is not allowed in this version number'
          end
          case value
            when 'ALL'
              result = configatron.product.version
            when 'MAJOR'
              result = configatron.product.version.split('.')[0]
            when 'MINOR'
              result = configatron.product.version.split('.')[1]
            when 'BUILD'
              result = configatron.product.version.split('.')[2]
            when 'REVISION'
              result = configatron.product.version.split('.')[3]
          end              
      end
      result
    end
    return version
  end
    
  def Raketools.parse_numeric_version()
    preprocessed_version = build_version(configatron.product.version, false)    
    major, minor, build, revision = preprocessed_version.split('.')
    res = [major, minor, build, revision].collect { |part| part.to_i}
    return res.join('.')
  end
  
  def Raketools.init()  
    return if @initialized
    configure()
    configatron.protect_all!
    @initialized = true
    CLEAN << configatron.dir.build
    CLEAN << configatron.dir.reports
  end 
  
  def Raketools.prepare_build()
    FileUtils.mkdir_p (configatron.dir.output)
    FileUtils.mkdir_p (configatron.dir.build)
    FileUtils.mkdir_p (configatron.dir.reports)  
  end
  
  def Raketools.versioninfo(options = {})
    Raketools.prepare_build()
    Dir.glob(File.join(configatron.dir.source, "**", "*.csproj")).each do |project|
      dir = File.dirname(project).to_absolute
      probe_properties = File.join(dir, 'Properties')      
      file = File.join(dir, "VersionInfo.cs") if !Dir.exists?(probe_properties)
      file = File.join(probe_properties, "VersionInfo.cs") if Dir.exists?(probe_properties)
      attributes = { 
        :AssemblyVersion => configatron.product.assemblyversion,        
        :AssemblyFileVersion => configatron.product.fileversion,
        :AssemblyInformationalVersion => configatron.product.informationalversion,
        :AssemblyConfiguration => configatron.build.config
      }
      log(__method__, "Generating #{file}")
      template = %q{
          <%= configatron.generate.versioninfohead %>
		  // This file is generated automatically. Do not edit manually.
          using System;
          using System.Reflection;
          using System.Runtime.InteropServices;
       
          <% attributes.each do |key, value| %>
            [assembly: <%= key %>("<%= value %>")]
          <% end %>
        }.gsub(/^\s+/, '')
        erb = ERB.new(template, 0, "%")       
        File.open(file, 'w') do |f|
          f.puts erb.result(binding)
        end
    end     
  end
  
  def Raketools.msbuild(options = {}) 
      Raketools.prepare_build()
      properties = { 
        :OutputPath => configatron.dir.build.to_argpath,
        :Configuration => configatron.build.config
      }     
      if !configatron.build.keyfile.nil?
        keyfile = configatron.build.keyfile.to_absolute
        if not File.exists? keyfile
          log(__method__, "Could not find key file #{keyfile}, skipping assembly signing")
        else
          properties[:SignAssembly] = 'true'
          properties[:AssemblyOriginatorKeyFile] = keyfile.to_argpath
          properties[:DelaySign] = configatron.build.delaysign
          properties[:AdditionalConstants] = 'SIGNED'
        end
      end            
      properties.merge!(options.fetch(:properties, {}))   
      
      switches = { 
        :nologo => true, 
        :maxcpucount => true, 
        :verbosity => configatron.build.verbose ? 'normal' : 'minimal' 
      }      
      
      switches.merge!( options.fetch(:switches, {}))      
     
      loggerpath  = File.join(configatron.dir.tools, 'msbuildlogger', 'Rodemeyer.MsBuildToCCnet.dll')
      enable_logger =  File.exists? (loggerpath)
      log(__method__, "Rodemeyer.MsBuildToCCnet.dll not found. Provide your own logger as a switch.") if not enable_logger
      framework_dir = File.join(ENV['WINDIR'].dup, 'Microsoft.NET', 'Framework', options.fetch("clr", "v4.0.30319"))            
      exe = File.join(framework_dir, "msbuild.exe")
      if not File.exists?(exe)
        framework_dir = File.join(ENV['WINDIR'].dup, 'Microsoft.NET', 'Framework', options.fetch("clr", "v3.5"))            
        exe = File.join(framework_dir, "msbuild.exe")
        if not File.exists?(exe)
          raise "Could not find msbuild.exe in #{framework_dir}. Did you provide a valid CLR version number?"
        end
      end
      
      log(__method__, "MSBuild found at #{exe}")
            
      get_solutions().collect{|k,v| v[:file]}.each do |solution| 
        log(__method__, "Building #{solution}")
        if enable_logger
          logfile = report( "MSBuild", File.basename(solution))
          switches[:logger] = "#{loggerpath.to_absolute.to_argpath};#{logfile.to_absolute.to_argpath}"
        end        
        propertyargs = properties.collect { |key, value| "/property:#{key}=#{value}" }.join(" ")
        switchargs = make_switches( switches )      
        final_cmd = "#{exe.to_argpath} #{solution.to_argpath} #{switchargs} #{propertyargs}"         
        run final_cmd
      end      
  end
  
  def Raketools.nunit(options = {})    
    return if not configatron.test.enabled 
    Raketools.prepare_build()
    
    nunit_exe = Raketools.get_tool('nunit')    
    if nunit_exe.nil?
      log(__method__, 'NUnit not found. Skipping unit tests')
      return
    end
    nunit_exe  = nunit_exe.to_argpath if nunit_exe != nil
    partcover_exe = Raketools.get_tool('partcover')
    partcover_exe = partcover_exe.to_argpath if partcover_exe != nil
    
    log(__method__, 'PartCover not found. Skipping coverage analysis.') if options.fetch(:coverage, configatron.test.coverage) and partcover_exe.nil?
    
    candidates = get_projects().collect { |k,v| v[:output_path]}.select { |k| k.match(/\.Tests\.dll$/)}    
    if candidates.length == 0
      log(__method__, 'No assemblies with unit tests found.')
      return 
    end
    candidates.each do |assembly|
      log(__method__, "Running tests in #{assembly}")
      assembly = assembly.to_absolute
      report_file =  report('NUnit', File.basename(assembly)).to_argpath
            
      if !options.fetch(:coverage, configatron.test.coverage) || partcover_exe == nil    
        nunit_switches = { :nologo => true,  
                           :noshadow => true, 
						   :nodots => true,
                           :domain=>'single', # otherwise we need to copy the NUnit assemblies to output dir
                           :xml => report_file}
        nunit_switches.merge!(options.fetch(:options, {}))
        argstring = make_switches( nunit_switches, '=' )
        nunit_cmd = "#{nunit_exe} #{assembly.to_argpath} #{argstring}"  
        run nunit_cmd
      else      
         nunit_switches = { :nologo => true,  
                            :noshadow => true, 
							:nodots => true,
                            :domain=>'single',
                            :xml => report_file}
        nunit_switches.merge!(options.fetch(:options, {}))
        argstring = make_switches( nunit_switches, '=' )
        nunit_cmd = "#{nunit_exe} #{assembly.to_argpath} #{argstring}"
        
		test_assembly = File.filename_without_ext(assembly)
		tested_assembly = test_assembly[0..-(".Tests".length+1)]
        switches = {
		  "log" => 0,
		  "target" => nunit_exe,
		  "target-work-dir" => configatron.dir.build.to_argpath,
		  "target-args" => "#{assembly.to_argpath} #{argstring}".quote,
		  :output => report('Coverage', File.basename(assembly)),
		  :include => ["[#{test_assembly}]*", "[#{tested_assembly}]*"]
          }
        switches.merge!(options.fetch(:coverage_options, {}))
        argstring = make_switches( switches, ' ', '--' )
        cmd = "#{partcover_exe} #{argstring}"
		run cmd        		
      end             
    end
  end
  
  def Raketools.fxcop(options = {})
    return if not configatron.analysis.enabled 
    Raketools.prepare_build()
    fxcop_exe = get_tool('fxcop')
    if fxcop_exe.nil?
      log(__method__, 'FxCop not found. Skipping analysis.')
      return
    end
    
    projects = Dir.glob(File.join(configatron.dir.source, "**", "*.FxCop"))
    if projects.length == 0
     log(__method__, 'No FxCop projects found.')
     return
    end
    projects.each do |project|      
      log(__method__, "Running #{project}")
      report_file = report("FxCop", File.basename(project))
      project = project.to_argpath
      switches = {       
        :quiet => configatron.build.verbose == false,
        :project => project, 
        :out => report_file  }
      switches.merge!(options.fetch(:switches, {}))
      switches = make_switches(switches)
      cmd = "#{fxcop_exe.to_argpath} #{switches}"      
      run cmd
    end
  end
  
  def Raketools.stylecop(options={})
    return if not configatron.analysis.enabled 
    Raketools.prepare_build()
    stylecmd_exe = get_tool('stylecop')
    if stylecmd_exe == nil
      log(__method__, 'StyleCopCmd not found. Skipping analysis.')
      return
    end
    solutions = get_solutions().collect{ |k,v| v[:file].to_argpath }
    if solutions.length == 0
      log(__method__, 'No solution files found for analysis.') if solutions.length == 0
      return
    end    
    log(__method__, "Analysing #{solutions.length} #{solutions.length == 1 ? 'solution' : 'solution'}")
    solutions = solutions.join(' ')
    switches = { 
      :solutionFiles => solutions,
      :outputXmlFile => report('StyleCop').to_argpath,
      :recurse => true,
      :ignoreFilePattern => "(([Pp]roduct|[Aa]ssembly|[Vv]ersion)Info\..+)|(.+\.[Dd]esigner\..+)".quote
      }
    switches.merge!(options.fetch(:switches, {}))
    switches = make_switches(switches, ' ', '-')
    cmd = "#{stylecmd_exe.to_argpath} #{switches}"	
    run cmd    
  end  
  
  def Raketools.gendarme(options={})
    return if not configatron.analysis.enabled 
    Raketools.prepare_build()
    gendarme_exe = get_tool('gendarme')
    if gendarme_exe == nil
      log(__method__, 'Gendarme not found. Skipping analysis.')
      return
    end
    output_types = {
              'Library'  => { :ext=>'.dll', :search_key =>'AssemblyName'},
              'Exe'      => { :ext=>'.exe', :search_key =>'AssemblyName'},
              'WinExe'   => { :ext=>'.exe', :search_key =>'AssemblyName'},
              'Package'  => { :ext=>'.msi', :search_key =>'OutputName'},
      }
    min_depth = File.absolute_path(configatron.dir.source).split(/[\/\\]/).length
    projects = get_projects().collect{|k,v| v}
    if projects.length == 0
      log(__method__, "No projects found")
      return
    end
    
    solutions = get_solutions().collect{ |k,v| v }
    if solutions.length == 0
      log(__method__, "No solutions found")
      return
    end
    
    solutions.each do |solution|
      solution_file = solution[:file]
      log(__method__, "Analyzing #{File.basename(solution[:file])}")   
      
      # try to determine the ignore file
      probe_dir = File.dirname(solution_file)
      ignore_file = nil
      while probe_dir.split(/[\/\\]/).length >= min_depth
        probe_path = File.join(probe_dir, configatron.gendarme.ignorefile)
        ignore_file = probe_path if File.exists? probe_path
        probe_dir = File.dirname(probe_dir)
      end
      switches = {
        :xml => report('Gendarme', File.filename_without_ext(solution_file)).to_argpath,
        :quiet => configatron.build.verbose == false
      }
      switches[:ignore] = ignore_file.to_argpath if not ignore_file.nil?
      
      switches.merge!(options.fetch(:switches, {}))
      switch_args = make_switches(switches, ' ', '--')      
      project_args = projects.collect{|p| p[:output_path].to_argpath}.join(' ')
      cmd = "#{gendarme_exe.to_argpath} #{switch_args} #{project_args}"
      run cmd
    end
  end  
  
  def Raketools.simian(options={})
    return if not configatron.analysis.enabled 
    Raketools.prepare_build()
    simian_exe = get_tool('simian')
    if simian_exe == nil
      log(__method__, 'Simian not found. Skipping analysis.')
      return
    end
    all_files = get_projects().select{|k,v| v[:type]=='csproj'}.collect do |k,v|    
      project = v[:file]
      dir = File.dirname(project)
      [File.join(dir.to_absolute, "*.cs"),File.join(dir.to_absolute, "**", "*.cs")].collect {|x| x.to_argpath} .join(' ')
    end 
    if all_files.length == 0
      log(__method__, "No projects found")
      return
    end
    all_files = all_files.join(' ')    
    switches = {
      :excludes =>  ["AssemblyInfo.*", "VersionInfo.*", "*.designer.*"].collect { |file| File.join(configatron.dir.source, "**", file).to_argpath},
      :failOnDuplication => false,
      :reportDuplicateText => true,
      :threshold => 6,
      :formatter => "xml:#{report('Simian').to_argpath}"      
    }
    switch_args = make_switches_with_bool(switches, '=', '-')
    cmd = "#{simian_exe.to_argpath} #{switch_args} #{all_files}"
    run cmd
  end  

  # Merges multiple assemblies into one.  
  #
  # Either include_pattern or inputs are required.
  #
  # options:
  #  :primary         => name of the output assembly
  #  :include_pattern => inclusion pattern (glob)
  #  :exclude_pattern => exclusion pattern (glob)
  #  :inputs          => additional files to merge
  #  :output          => output file name
  #  switches => {
  #      :lib            => search dirs (array),
  #      :log            => true|false or log file,
  #      :keyfile        => key file,
  #      :delaysign      => true|false,
  #      :internalize    => true|false or name of exclude file,
  #      :target         => exe|winexe|library,
  #      :closed         => true|false,
  #      :ndebug         => true|false,
  #      :ver            => new version,
  #      :copyattrs      => true|false,
  #      :allowMultiple  => true|false,
  #      :xmldocs        => true|false,
  #      :attr           => attribute file,
  #      :targetplatform => 'v1|v1.1|v2|v4',
  #      :useFullPublicKeyForReferences => true,
  #      :zeroPeKind     => true|false,
  #      :wildcards      => true|false,
  #      :allowDup       => duplicate names (array),
  #      :union          => true|false,
  #      :align          => file alignment in bytes        
  #  }
  #
  # Typical example:
  #
  # Raketools.ilmerge({
  #  :primary => 'MyApp.exe',
  #  :include_pattern => 'MyApp.*.dll',    
  #  :exclude_pattern => '*.Tests.dll'
  # })
  #
  # Merges MyApp and all libraries starting with MyApp.
  # except test assemblies into MyApp.Merged.exe  
  #
  #
  def Raketools.ilmerge(options = {})    
    Raketools.prepare_build()
    if !options.has_key?(:primary)
        raise "ilmerge: option 'primary' required"
    end
    
    primary = File.join(configatron.dir.build, options[:primary]).to_argpath
    
     # determine output
    output = File.join(configatron.dir.build, options.fetch(:output, "#{File.filename_without_ext(options[:primary])}.Merged#{File.extname(options[:primary])}"))
    output = output.to_argpath
    
    # determine inputs
    inputs = options[:inputs]
    if inputs.nil?
        raise "You need to provide an include or a specific include list" if !(options.has_key?(:include_pattern) or options.has_key?(:exclude_pattern))
        # auto collect inputs
        inputs = as_array(options[:include_pattern]).collect{|i| Dir.glob(File.join(configatron.dir.build, i))}.flatten.uniq
        inputs = inputs - as_array(options[:exclude_pattern]).collect{|i| Dir.glob(File.join(configatron.dir.build, i))}.flatten if options.has_key?(:exclude_pattern)
    else
        inputs = as_array(inputs).collect { |inp| File.join(configatron.dir.build, inp)}        
    end
    
    inputs = (inputs.collect{|inp|inp.to_argpath} - [primary, output])
    log(__method__, "Primary: #{primary}")
    inputs.each{|i| log(__method__, "Input:   #{i}")}
    log(__method__, "Output:  #{output}")    
    log(__method__, "Merging #{1+inputs.length} assemblies to #{output}")
    
    ilmerge_exe = Raketools.get_tool('ilmerge')   
    
    if ilmerge_exe.nil?
        raise "Could not find ILMerge.exe"
    end
    
    opts = options[:switches]
    opts = {} if opts.nil?
    switches = make_switches(opts, '=', '/', true)
    
    ilmerge_cmd = "#{ilmerge_exe} #{switches} /out:#{output} #{primary} #{inputs.join(' ')}"
    
    run ilmerge_cmd    
  end
  
  def Raketools.get_projects()
    return @projects if !@projects.nil?
    
    output_types = {
              'Library'  => { :ext=>'.dll', :search_key =>'AssemblyName'},
              'Exe'      => { :ext=>'.exe', :search_key =>'AssemblyName'},
              'WinExe'   => { :ext=>'.exe', :search_key =>'AssemblyName'},
              'Package'  => { :ext=>'.msi', :search_key =>'OutputName'},
      }
    projects = Dir.glob(File.join(configatron.dir.source, "**", "*.csproj"))
    @projects = Hash.new
   
    projects.each do |project|
      project = project       
      file = File.new(project.to_absolute)
      doc = REXML::Document.new(file)
      output_typename= REXML::XPath.first(doc, 'Project/PropertyGroup/OutputType').text
      output_type = output_types[output_typename]      
      output_name = REXML::XPath.first(doc, "Project/PropertyGroup/#{output_type[:search_key]}").text
      output_file = "#{output_name}#{output_type[:ext]}"
      output_path = File.join(configatron.dir.build, output_file)
      
      @projects[project] = {
        :file => project.to_absolute.to_winpath,
        :type => 'csproj',
        :output_name => output_name,
        :output_type => output_typename,
        :output_extension => output_type[:ext],
        :output_file => output_file,
        :output_path => output_path        
      }
    end
    return @projects
  end
  
  def Raketools.get_solutions()
    return @solutions if !@solutions.nil?
    
    solutions = Dir.glob(File.join(configatron.dir.source, "**", "*.sln"))
    @solutions = Hash.new
    solutions.each do |s|       
      @solutions[s] = {
        :file => s.to_absolute.to_winpath
      }
    end
    return @solutions
  end
  
  
  def Raketools.get_tool(name)
     tool = configatron.tool.retrieve(name, nil)
     return nil if tool == nil         
     file = tool.to_winpath.to_absolute
     file = nil if not File.exists?(file)
     return file
  end
  
  def Raketools.report(cat, name=nil, ext="xml")
    File.expand_path(File.join(configatron.dir.reports, "#{cat}#{"-#{name}" unless name.nil?}.#{ext}"))
  end
  
  def Raketools.make_switches(switches, sep=':', prefix='/', quote=false)    
    switches.collect do |key, value| 
      (value.is_a? Array) ? value.collect { |v| render_switch(key, v, sep, prefix,quote) }.join(' ') :  render_switch(key, value, sep, prefix,quote)
    end.join(" ")
  end
  
  def Raketools.make_switches_with_bool(switches, sep=':', prefix='/', quote=false)
    switches.collect do |key, value| 
      (value.is_a? Array) ? value.collect { |v| render_switch_bool(key, v, sep, prefix, quote) }.join(' ') :  render_switch_bool(key, value, sep, prefix, quote)
    end.join(" ")
  end
  
  def Raketools.render_switch(key,value,sep,prefix,quote)
    res = "#{prefix}#{key}#{"#{sep}#{value}" unless value.kind_of? TrueClass or value.kind_of? FalseClass}" if value 
    res = "\"#{res}\"" if quote
    res    
  end
  
  def Raketools.render_switch_bool(key,value,sep,prefix,quote)
    res = "#{prefix}#{key}+"  if value.kind_of? TrueClass
    res = "#{prefix}#{key}-"  if value.kind_of? FalseClass
    res = "#{prefix}#{key}#{sep}#{value}" unless (value.kind_of? TrueClass or  value.kind_of? FalseClass)
    res = "\"#{res}\"" if quote
    res 
  end
  
  def Raketools.log(name, message)
    puts "[#{name}] #{message}"
  end
  
  def Raketools.run(cmd)
    if configatron.build.verbose 
      sh cmd
    else
      Kernel.system cmd    
    end
  end
  
  def Raketools.as_array(what)
    return what if what.kind_of? Array
    return [what]
  end
  
  # GIT CALLS
  def Raketools.git_commit_count_in_branch()
    `git rev-list HEAD | wc -l`.to_i
  end
  
  def Raketools.git_current_commit_hash(abbreviate)
    if abbreviate
      return `git rev-parse --short=8 HEAD` .strip()
    else
      return `git rev-parse HEAD`.strip()
    end
  end
  
  def Raketools.git_current_branch()
    `git branch --no-color`.each_line.select{|l| l =~ /^\*\s/ }.collect{|l| l.sub(/^\*/, '')}[0].strip()
  end
  
    def Raketools.git_describe_version(depth)
    describe = `git describe --tags`
    match = /^(?:v?)(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.(\d+))?/ix.match(describe)
    (match ? match.captures.collect { |c| c.to_i } : [0,0,0,0]).slice(0..(depth-1))          
  end 
  
  def Raketools.git_describe_commits()
    describe = `git describe --tags`
    match = /^(?:v?\d+(?:\.\d+)?(?:\.\d+)?(?:\.\d+)?)-(\d+)/ix.match(describe)
    return match ? match.captures[0].to_i : 0
  end   
  
end

class Rake::Task
	old_execute = self.instance_method(:execute)	
	define_method(:execute) do |args|    
		puts "\n[TASK: #{name}]\n" if configatron.build.exists?(:verbose) and configatron.build.verbose
		old_execute.bind(self).call(args)
	end
end

class String
  def quote()
    "\"#{self.gsub(/\"/, '\\"')}\""
  end
  
  def to_argpath()
    to_winpath.to_absolute.quote
  end
  
  def to_winpath()
    self.gsub(/\//, "\\")
  end 
  
  def to_absolute()
     return File.absolute_path(self)
  end
end

class File
  def self.filename_without_ext(path)
    File.basename(path, File.extname(path))
  end
end

class Object
  def to_b()
    if self.kind_of? TrueClass or self.kind_of? FalseClass
      return self
    elsif self.kind_of? String
      return self.match(/(true|t|yes|y|1)$/i) != nil
    else
      raise "Can't convert #{self.to_s} to bool"
    end
  end
end