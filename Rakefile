require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "drupal-deploy"
    gemspec.summary = "A Drupal focused replacement for the default Capistrano tasks"
    gemspec.description = "Replacement for the rails deploy strategy which ships with Capistrano, allows you to deploy Drupal sites with ease.  Based off of Lee Hambley's Railsless Deploy."
		gemspec.add_dependency 'capistrano-ext'
    gemspec.email = "ehassick@gmail.com"
    gemspec.homepage = "http://github.com/jh3/drupal-deploy"
    gemspec.authors = ["Joe Hassick"]
  end
	Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
