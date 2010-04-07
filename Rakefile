require 'rubygems'
require 'rake'
require 'cucumber/rake/task'
require 'date'

TEST_PROJECT = 'test_project'
VERSION = '0.0.1'

#############################################################################
#
# Testing functions
#
#############################################################################

Cucumber::Rake::Task.new

namespace :test do
  desc "A full suspenders app's test suite"
  task :full => ['generate:suspenders', 'generate:finish', 'cucumber', 'destroy:suspenders']
end

namespace :generate do
  desc 'Suspend a new project'
  task :suspenders do
    sh './bin/suspension', TEST_PROJECT
  end

  desc 'Finishing touches'
  task :finish do
    open(File.join(TEST_PROJECT, 'config', 'environments', 'cucumber.rb'), 'a') do |f|
      f.puts "config.action_mailer.default_url_options = { :host => 'localhost:3000' }"
    end

    routes_file = IO.read(File.join(TEST_PROJECT, 'config', 'routes.rb')).split("\n")
    routes_file = [routes_file[0]] + [%{map.root :controller => 'clearance/sessions', :action => 'new'}] + routes_file[1..-1]
    open(File.join(TEST_PROJECT, 'config', 'routes.rb'), 'w') do |f|
      f.puts routes_file.join("\n")
    end
  end
end

namespace :destroy do
  desc 'Remove a suspended project'
  task :suspenders do
    FileUtils.rm_rf TEST_PROJECT
  end
end

desc 'Run the test suite'
task :default => ['test:full']

#############################################################################
#
# Helper functions
#
#############################################################################

def name
  @name ||= Dir['*.gemspec'].first.split('.').first
end

def version
  VERSION
end

def date
  Date.today.to_s
end

def gemspec_file
  "#{name}.gemspec"
end

def gem_file
  "#{name}-#{version}.gem"
end

def replace_header(head, header_name)
  head.sub!(/(\.#{header_name}\s*= ').*'/) { "#{$1}#{send(header_name)}'"}
end

#############################################################################
#
# Packaging tasks
#
#############################################################################

task :release => :build do
  unless `git branch` =~ /^\* master$/
    puts "You must be on the master branch to release!"
    exit!
  end
  sh "git commit --allow-empty -a -m 'Release #{version}'"
  sh "git tag v#{version}"
  sh "git push origin master"
  sh "git push v#{version}"
  sh "gem push pkg/#{name}-#{version}.gem"
end

task :build => :gemspec do
  sh "mkdir -p pkg"
  sh "gem build #{gemspec_file}"
  sh "mv #{gem_file} pkg"
end

task :gemspec do
  # read spec file and split out manifest section
  spec = File.read(gemspec_file)
  head, manifest, tail = spec.split("  # = MANIFEST =\n")

  # replace name version and date
  replace_header(head, :name)
  replace_header(head, :version)
  replace_header(head, :date)

  # determine file list from git ls-files
  files = `git ls-files`.
    split("\n").
    sort.
    reject { |file| file =~ /^\./ }.
    reject { |file| file =~ /^(rdoc|pkg)/ }.
    map { |file| "    #{file}" }.
    join("\n")

  # piece file back together and write
  manifest = "  s.files = %w[\n#{files}\n  ]\n"
  spec = [head, manifest, tail].join("  # = MANIFEST =\n")
  File.open(gemspec_file, 'w') { |io| io.write(spec) }
  puts "Updated #{gemspec_file}"
end