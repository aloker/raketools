.NET Raketools
================

A small library of functions useful for .NET development.

Supported tools:

* MSBuild
* NUnit + NCover
* FxCop
* StyleCop
* Simian
* Gendarme

Simple example:

    require 'raketools/raketools' # required

    task :default => [:clobber, :compile, :test, :analyze] 

    task :compile => [:init] do
      Raketools.versioninfo() # create VersionInfo.cs files in the Properties directories
      Raketools.msbuild()     # compile all solutions
    end

    task :test => [:compile] do
      Raketools.nunit() # run NUnit and NCover on all .Tests.dll assemblies 
    end

    task :analyze => [:compile] do
      Raketools.fxcop()    # run .FxCop files
      Raketools.stylecop() # run StyleCop for all solutions
      Raketools.gendarme() # run Gendarme for all generated assemblies
      Raketools.simian()   # run simian for all .cs files in the source directory
    end