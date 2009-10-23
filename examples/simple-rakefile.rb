require 'raketools/raketools'

task :default => [:clobber, :compile, :test, :analyze]

task :compile => [:init] do
  Raketools.versioninfo()
  Raketools.msbuild()
end

task :test => [:compile] do
  Raketools.nunit()
end

task :analyze => [:compile] do
  Raketools.fxcop
  Raketools.stylecop
  Raketools.gendarme  
  Raketools.simian
end