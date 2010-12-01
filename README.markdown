# Drupal Deploy (Based off of Lee Hambley's Railsless Deploy)

If you want a way to deploy your drupal code, copy `files/` directory (and back it up), and dump and 
import your development database to another server (and back it up!) all by with 'cap deploy', this is for you.

Please visit the [wiki](http://github.com/jh3/drupal-deploy/wiki) for a couple of example files!

## Installation

$ gem install drupal-deploy

## Dependencies

`capistrano-ext`, the multi-stage extension for Capistrano, will be checked for while installing this.

## Usage

Begin your application's `Capfile` like this:

require 'rubygems'
require 'drupal-deploy'
load    'config/deploy'

Be sure to remove the original `require 'deploy'` as this is where the standard tasks are defined.  You don't want to use those.

Now proceed as you normally would.  I really, really recommend looking through the tasks that come with this, though.

Get a full task list with `cap -T`

## Assumptions

This deploy strategy makes a bunch of assumptions which you may or may not like:

* You have [drush](http://drupal.org/project/drush) installed on your remote server(s)
* Your `files/` directory is in the standard location, `sites/default`
* Your site's code lives in a directory named `drupal/`

Your site's directory structure should resemble this:

    my_website/
    `- .git/
    `- .gitignore
    `- Capfile
    `- config/
      `- deploy.rb
      `- deploy/
        `- staging.rb
        `- production.rb
    `- drupal/
      `- <drupal files>

## What's Included?

If you want to try before you buy, here's the list of tasks included with this version of the deploy recipe:

    cap deploy                    # Deploys your project.
    cap deploy:check              # Test deployment dependencies.
    cap deploy:cleanup            # Clean up old releases.
    cap deploy:db                 # Dumps and imports the development database to your live site
    cap deploy:db:pull            # Dumps and imports the live database to the development site
    cap deploy:files              # Copies the files directory from development to live
    cap deploy:files:pull         # Pull the files directory from the live server to development
    cap deploy:pending            # Displays the commits since your last deploy.
    cap deploy:pending:diff       # Displays the `diff' since your last deploy.
    cap deploy:pull               # Pull the database and files directory from your primary server to your secondary server
    cap deploy:rollback           # Rolls back to a previous version and restarts.
    cap deploy:setup              # Prepares one or more servers for deployment.
    cap deploy:update             # Copies your project and updates the symlink.
    cap deploy:update_code        # Copies your project to the remote servers.
    cap deploy:upload             # Copy files to the currently deployed version.
    cap drupal:configure:settings # Copy the appropriate settings.php file.
    cap drupal:symlink:webapp     # Symlink the website
    cap invoke                    # Invoke a single command on the remote servers.
    cap shell                     # Begin an interactive Capistrano session.

I recommend running `cap -vT` too and looking through everything.  There are a bunch of internal tasks at work.

## Bugs & Feedback

Questions?  Feedback?  Love it?  Hate it?  Want to fix it?  Anything else?  Let me know.

http://github.com/jh3
