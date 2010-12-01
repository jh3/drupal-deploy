Capistrano::Configuration.instance(:must_exist).load do

  require 'capistrano/recipes/deploy/scm'
  require 'capistrano/recipes/deploy/strategy'

  def _cset(name, *args, &block)
    unless exists?(name)
      set(name, *args, &block)
    end
  end

  # =========================================================================
  # These variables MUST be set in the client capfiles. If they are not set,
  # the deploy will fail with an error.
  # =========================================================================

  _cset(:application) { abort "Please specify the name of your application, set :application, 'foo'" }
  _cset(:repository)  { abort "Please specify the repository that houses your application's code, set :repository, 'foo'" }

  # =========================================================================
  # These variables may be set in the client capfile if their default values
  # are not sufficient.
  # =========================================================================

  _cset :scm, :git
  _cset :deploy_via, :remote_cache

  _cset(:deploy_to) { "/u/apps/#{application}" }
  _cset(:revision)  { source.head }

  # =========================================================================
  # These variables should NOT be changed unless you are very confident in
  # what you are doing. Make sure you understand all the implications of your
  # changes if you do decide to muck with these!
  # =========================================================================

  _cset(:source)            { Capistrano::Deploy::SCM.new(scm, self) }
  _cset(:real_revision)     { source.local.query_revision(revision) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } } }

  _cset(:strategy)          { Capistrano::Deploy::Strategy.new(deploy_via, self) }

  _cset(:release_name)      { set :deploy_timestamped, true; Time.now.utc.strftime("%Y%m%d%H%M%S") }
  _cset(:db_snapshot_name)  { "#{release_name}-snapshot.sql" }
  _cset(:file_archive_name) { "#{release_name}-files.tar" }

  _cset :version_dir,       "releases"
  _cset :shared_dir,        "shared"
  _cset :shared_children,   %w(dumps files files_backup)
  _cset :current_dir,       "current"

  _cset(:releases_path)     { File.join(deploy_to, version_dir) }
  _cset(:shared_path)       { File.join(deploy_to, shared_dir) }
  _cset(:databases_path)		{ File.join(deploy_to, shared_dir, shared_children[0]) }
  _cset(:files_path)				{ File.join(deploy_to, shared_dir, shared_children[1]) }
  _cset(:files_backup_path) { File.join(deploy_to, shared_dir, shared_children[2]) }
  _cset(:current_path)      { File.join(deploy_to, current_dir) }
  _cset(:release_path)      { File.join(releases_path, release_name) }

  _cset(:releases)          { capture("ls -xt #{releases_path}").split.reverse }
  _cset(:databases)         { capture("ls -xt #{databases_path}").split.reverse }
  _cset(:files_backup)      { capture("ls -xt #{files_backup_path}").split.reverse }

  _cset(:current_release)   { File.join(releases_path, releases.last) }
  _cset(:current_database)  { File.join(databases_path, databases.last) }
  _cset(:current_files)     { File.join(files_backup_path, files_backup.last) }

  _cset(:previous_release)  { releases.length > 1 ? File.join(releases_path, releases[-2]) : nil }
  _cset(:previous_database) { databases.length > 1 ? File.join(databases_path, databases[-2]) : nil }
  _cset(:previous_files)		{ files_backup.length > 1 ? File.join(files_backup_path, files_backup[-2]) : nil }

  _cset(:current_revision)  { capture("cat #{current_path}/REVISION").chomp }
  _cset(:latest_revision)   { capture("cat #{current_release}/REVISION").chomp }
  _cset(:previous_revision) { capture("cat #{previous_release}/REVISION").chomp }

  _cset(:run_method)        { fetch(:use_sudo, true) ? :sudo : :run }

  # some tasks, like symlink, need to always point at the latest release, but
  # they can also (occassionally) be called standalone. In the standalone case,
  # the timestamped release_path will be inaccurate, since the directory won't
  # actually exist. This variable lets tasks like symlink work either in the
  # standalone case, or during deployment.
  _cset(:latest_release) { exists?(:deploy_timestamped) ? release_path : current_release }

  # This assumes that drupal lives in its own directory named 'drupal'
  _cset(:drupal_root)		 { File.join(current_release, 'drupal') }

  # =========================================================================
  # These are helper methods that will be available to your recipes.
  # =========================================================================

  # Auxiliary helper method for the `deploy:check' task. Lets you set up your
  # own dependencies.
  def depend(location, type, *args)
    deps = fetch(:dependencies, {})
    deps[location] ||= {}
    deps[location][type] ||= []
    deps[location][type] << args
    set :dependencies, deps
  end

  # Temporarily sets an environment variable, yields to a block, and restores
  # the value when it is done.
  def with_env(name, value)
    saved, ENV[name] = ENV[name], value
    yield
  ensure
    ENV[name] = saved
  end

  # logs the command then executes it locally.
  # returns the command output as a string
  def run_locally(cmd)
    logger.trace "executing locally: #{cmd.inspect}" if logger
    `#{cmd}`
  end

  # If a command is given, this will try to execute the given command, as
  # described below. Otherwise, it will return a string for use in embedding in
  # another command, for executing that command as described below.
  #
  # If :run_method is :sudo (or :use_sudo is true), this executes the given command
  # via +sudo+. Otherwise is uses +run+. If :as is given as a key, it will be
  # passed as the user to sudo as, if using sudo. If the :as key is not given,
  # it will default to whatever the value of the :admin_runner variable is,
  # which (by default) is unset.
  #
  # THUS, if you want to try to run something via sudo, and what to use the
  # root user, you'd just to try_sudo('something'). If you wanted to try_sudo as
  # someone else, you'd just do try_sudo('something', :as => "bob"). If you
  # always wanted sudo to run as a particular user, you could do 
  # set(:admin_runner, "bob").
  def try_sudo(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    command = args.shift
    raise ArgumentError, "too many arguments" if args.any?

    as = options.fetch(:as, fetch(:admin_runner, nil))
    via = fetch(:run_method, :sudo)
    if command
      invoke_command(command, :via => via, :as => as)
    elsif via == :sudo
      sudo(:as => as)
    else
      ""
    end
  end

  # Same as sudo, but tries sudo with :as set to the value of the :runner
  # variable (which defaults to "app").
  def try_runner(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    args << options.merge(:as => fetch(:runner, "app"))
    try_sudo(*args)
  end

  # Attempts to grab the user and host from a specific 'web' role.  If the
  # role has its own user, it will use that.  Otherwise, the user set either
  # in the Capfile or any specific stage file will be used.
  #
  # If the specific web role cannot be found, it will abort with an error
  # message.
  def web_role(rank)
    server = ''
    find_servers( { :roles => :web, :only => { rank => true } } ).each do |s|
      server = s.user ? "#{s.user}@#{s.host}" : "#{user}@#{s.host}"
    end

    if server.length > 0
      server
    else
      abort "The option '#{rank}' is not applied to any of your 'web' roles"
    end
  end

  # =========================================================================
  # These are the tasks that are available to help with deploying web apps,
  # and specifically, Rails applications. You can have cap give you a summary
  # of them with `cap -T'.
  # =========================================================================

  namespace :deploy do
    desc <<-DESC
      Deploys your project. Handy wrapper to hook into the beginning of the deployment. Note that \
      this will generally only work for applications that have already been deployed \
      once.
    DESC
    task :default do
      update
    end

    desc <<-DESC
      Prepares one or more servers for deployment. Before you can use any \
      of the Capistrano deployment tasks with your project, you will need to \
      make sure all of your servers have been prepared with `cap deploy:setup'. When \
      you add a new server to your cluster, you can easily run the setup task \
      on just that server by specifying the HOSTS environment variable:

        $ cap HOSTS=new.server.com deploy:setup

      It is safe to run this task on servers that have already been set up; it \
      will not destroy any deployed revisions or data.
    DESC
    task :setup, :except => { :no_release => true } do
      dirs = [deploy_to, releases_path, shared_path]
      dirs += shared_children.map { |d| File.join(shared_path, d) }
      run "#{try_sudo} mkdir -p #{dirs.join(' ')} && #{try_sudo} chmod g+w #{dirs.join(' ')}"
      run "#{try_sudo} chown -R #{user}:#{group} #{deploy_to}"
    end

    desc <<-DESC
      Copies your project and updates the symlink.  It does this in a \
      transaction, so that if any of the tasks fail, all changes made \
      to the remote servers will be rolled back, leaving your system in \
      the same state it was in before 'update' was invoked.  Usually, you \
      will want to call 'deploy' instead of 'update'.
    DESC
    task :update do
      transaction do
        files.default
        update_code
        symlink
        db.default
      end
    end

    desc <<-DESC
      Copies your project to the remote servers. This is the first stage \
      of any deployment; moving your updated code and assets to the deployment \
      servers. You will rarely call this task directly, however; instead, you \
      should call the `deploy' task (to do a complete deploy) or the `update' \
      task (if you want to perform the `restart' task separately).

      You will need to make sure you set the :scm variable to the source \
      control software you are using (it defaults to :git), and the \
      :deploy_via variable to the strategy you want to use to deploy (it \
      defaults to :remote_cache).
    DESC
    task :update_code, :except => { :no_release => true } do
      on_rollback { run "rm -rf #{release_path}; true" }
      strategy.deploy!
      finalize_update
    end

    namespace :files do
      namespace :pull do
        desc "[internal] Set the temporary filename for the files archive"
        task :filename, :except => { :no_release => true } do
          set :tmp_filename, "/tmp/#{application}-#{stage}-files.bz2"
        end

        desc <<-DESC
          [internal] Compresses the files directory located on your primary web \
          server and sends it to your secondary web server.  You asked twice \
          before it actually removes/overrides anything, just in case.  

          If this task is aborted after the 'compress' tasks executes, the \
          archive is deleted.

          It is possible, to call this task, but it's a little easier to just \
          run 'files:pull'.
        DESC
        task :paranoid_execute, :except => { :no_release => true } do
          filename 
          Capistrano::CLI.ui.say("You are about to pull the files directory from #{stage} and send it to your development server.")
          answer = Capistrano::CLI.ui.ask("Are you sure you want to do this? (y[es]/n[o]): ")
          answer = answer.match(/(^y(es)?$)/i)

          if answer
            compress
            Capistrano::CLI.ui.say("The files directory has been compressed and sent from #{stage} to your secondary machine.")
            Capistrano::CLI.ui.say("This next step will remove the files directory on your development machine.")
            answer = Capistrano::CLI.ui.ask("Are you sure you want to continue? (y[es]/n[o]): ")
            answer = answer.match(/(^y(es)?$)/i)

            if answer
              decompress
            else
              rollback
            end
          else
            abort "Files directory pull from #{stage} aborted!"
          end
        end

        desc <<-DESC
          [internal] Creates a compressed archive of the files directory on your \
          primary web server.  Then it is copied to your secondary web server and \
          the original file is removed.  Do not call this task directly.  Instead \
          let 'paranoid_execute' run this.
        DESC
        task :compress, :roles => :web, :only => { :primary => true } do
          filename 
          execute = []
          execute << "cd #{shared_path}"
          execute << "tar cjf #{tmp_filename} files/"
          execute << "scp #{tmp_filename} #{web_role(:secondary)}:#{tmp_filename}"
          execute << "rm #{tmp_filename}"
          run execute.join(" && ")
        end

        desc <<-DESC
          [internal] Removes the files directory on your secondary server and \
          replaces it with the files archive created by the 'compress' task.
          Do not call this task directly.  Instead let 'paranoid_execute' run this.
        DESC
        task :decompress, :roles => :web, :only => { :secondary => true } do
          filename
          execute = []
          execute << "#{try_sudo} rm -rf #{application_wd}/sites/default/files"
          execute << "#{try_sudo} tar xjf #{tmp_filename} -C #{application_wd}/sites/default"
          execute << "#{try_sudo} rm #{tmp_filename}" 
          run execute.join(" && ")
        end

        desc <<-DESC
          [internal] Removes the files archive if the 'paranoid_execute' task is \
          aborted.  Do not call this task directly.  Instead let 'paranoid_execute' \
          handle running this if necessary.
        DESC
        task :rollback, :roles => :web, :only => { :secondary => true } do
          filename
          try_sudo "rm #{tmp_filename}"
          abort "Files directory pull was aborted before decompressing the archive.  The archive has been removed." 
        end

        desc "Pull the files directory from the live server to development"
        task :default, :except => { :no_release => true } do
          paranoid_execute
        end
      end

      desc "[internal] Sets several filenames before transferring the files directory"
      task :set_file_paths, :except => { :no_release => true } do
        tmpdir = '/tmp'

        set(:files_dir)				{ File.join(application_wd, 'sites/default') }
        set(:filename)				{ File.join(tmpdir, "#{file_archive_name}.bz2") }
        set(:remote_filename) { File.join(tmpdir, File.basename(filename)) }
      end

      desc <<-DESC
        [internal] Compresses the files directory on the secondary server \
        and sends them to the primary server.  Do not call this task directly.
      DESC
      task :copy, :roles => :web, :only => { :secondary => true } do
        set_file_paths

        execute = []
        execute << "cd #{files_dir}"
        execute << "tar cjf #{filename} files/"
        execute << "scp #{filename} #{web_role(:primary)}:#{remote_filename}"
        execute << "rm #{filename}"
        run execute.join(" && ")
      end

      desc <<-DESC
        [internal] Removes the existing files directory on the primary server and \
        unpacks the compressed files archive.  The compressed archive is saved \
        in 'shared/files_backup'.  

        In case of an error, the process is rolled back and the previous files \
        archive is restored.  Do not call this task directly.
      DESC
      task :unpack, :roles => :web, :only => { :primary => true } do
        on_rollback do
          if previous_files
            rollback
          else
            logger.important "no previous files archive to rollback to, rollback of files skipped"
          end
        end

        set_file_paths	

        execute = []
        execute << "#{try_sudo} rm -rf #{files_path}"
        execute << "tar xjf #{remote_filename} -C #{shared_path}"
        execute << "#{try_sudo} chown -R #{web_user}:#{web_user} #{files_path}"
        execute << "#{try_sudo} chown #{user}:#{group} #{files_path}"
        execute << "mv #{remote_filename} #{files_backup_path}"
        run execute.join(" && ")
      end

      desc <<-DESC
        [internal] Removes the existing files directory and restores a previous \
        archive.  This task should not be called directly.
      DESC
      task :rollback, :except => { :no_release => true } do
        run "#{try_sudo} rm -rf #{files_path}"
        run "#{try_sudo} tar xjf #{previous_files} -C #{shared_path}"
        run "#{try_sudo} chmod 775 #{files_path}"
        run "#{try_sudo} chown -R #{web_user}:#{web_user} #{files_path}"
        run "#{try_sudo} chown #{user}:#{group} #{files_path}"
      end

      desc "Copies the files directory from development to live."
      task :default, :except => { :no_release => true } do
        copy
        unpack
      end
    end

    desc <<-DESC
      [internal] Touches up the released code. This is called by update_code \
      after the basic deploy finishes.

      This task will make the release group-writable (if the :group_writable \
      variable is set to true, which is the default).  It will then setup the \
      correct permissions for the sites/default/files directory.  It is assumed \
      that your 'files' directory is in the standard location.  At the moment, \
      it is also assumed that your web user is apache.
    DESC
    task :finalize_update, :except => { :no_release => true } do
      run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
      run "#{try_sudo} chmod 775 #{files_path}"
      run "ln -s #{files_path} #{drupal_root}/sites/default/files"
    end

    desc <<-DESC
      [internal] Updates the symlink to the most recently deployed version. \
      Capistrano works by putting each new release of your application in its own \
      directory. When you deploy a new version, this task's job is to update the \
      'current' symlink to point at the new version. You will rarely need to call \
      this task directly; instead, use the `deploy' task.
    DESC
    task :symlink, :except => { :no_release => true } do
      on_rollback do
        if previous_release
          run "rm -f #{current_path}; ln -s #{previous_release}/drupal #{current_path}; true"
        else
          logger.important "no previous release to rollback to, rollback of symlink skipped"
        end
      end

      run "rm -f #{current_path} && ln -s #{latest_release}/drupal #{current_path}"
    end

    desc <<-DESC
      Copy files to the currently deployed version. This is useful for updating \
      files piecemeal, such as when you need to quickly deploy only a single \
      file. Some files, such as updated templates, images, or stylesheets, \
      might not require a full deploy, and especially in emergency situations \
      it can be handy to just push the updates to production, quickly.

      To use this task, specify the files and directories you want to copy as a \
      comma-delimited list in the FILES environment variable. All directories \
      will be processed recursively, with all files being pushed to the \
      deployment servers.

        $ cap deploy:upload FILES=templates,controller.rb

      Dir globs are also supported:

        $ cap deploy:upload FILES='config/apache/*.conf'
    DESC
    task :upload, :except => { :no_release => true } do
      files = (ENV["FILES"] || "").split(",").map { |f| Dir[f.strip] }.flatten
      abort "Please specify at least one file or directory to update (via the FILES environment variable)" if files.empty?

      files.each { |file| top.upload(file, File.join(current_path, file)) }
    end

    namespace :db do
      namespace :pull do
        desc <<-DESC
          [internal] Asks if you are sure you want to override the development \
          database with the primary server's database.  If anything but 'y' or 'yes' \
          is entered, the pull is aborted.
        DESC
        task :paranoid_execute, :roles => :web, :only => { :secondary => true } do
          Capistrano::CLI.ui.say("You are about to pull the database from #{stage} and import it to your development server.")
          answer = Capistrano::CLI.ui.ask("Are you sure you want to do this? (y[es]/n[o]): ")
          answer = answer.match(/(^y(es)?$)/i)

          if answer
            run "cd #{application_wd} && #{dump} | drush sql-cli"
          else
            abort "Database pull from #{stage} aborted!"
          end
        end

        desc <<-DESC
          [internal] The command used on the development server to pull down \
          the live database and import it.  This task should never be called \
          by itself.  If you want to execute this command, run 'db:pull' instead.
        DESC
        task :dump, :roles => :web, :only => { :primary => true } do
          cmd = "ssh #{web_role(:primary)} 'cd #{drupal_root} && drush -q cc all && drush sql-dump'"
        end

        desc <<-DESC
          Dumps the database from the primary server and imports it to the \
          development machine.
        DESC
        task :default, :except => { :no_release => true } do
          paranoid_execute
        end
      end

      desc <<-DESC
        [internal] Set the name of the database backup snapshot.  All snapshots \
        will be stored in shared/dumps and will contain that timestamp of the \
        release it is associated with.
      DESC
      task :snapshot_name, :except => { :no_release => true } do
        set :dump_file, "#{databases_path}/#{db_snapshot_name}"
      end

      desc <<-DESC
        [internal] Clears the cache on the development site, dumps the database, \
        and compresses it for storage.  All of the database snapshots sit in \
        shared/dumps. 

        It is assumed you have drush installed on your remote server.

        This task depends on the 'web' role(s).  The primary 'web' role is the \
        server that receives the compressed snapshot.  The secondary 'web' role \
        is assumed to be your development machine.  This task also relies on the \
        'application_wd' variable being set in the Capfile.

        This task is called by the 'deploy' task.
      DESC
      task :dump, :except => { :no_release => true } do
        snapshot_name

        primary = web_role(:primary)
        secondary = web_role(:secondary)

        execute = []
        execute << "ssh #{secondary} 'cd #{application_wd} && drush cc all'"
        execute << "ssh #{secondary} 'cd #{application_wd} && drush sql-dump' | bzip2 -c > /tmp/#{db_snapshot_name}.bz2"
        execute << "scp /tmp/#{db_snapshot_name}.bz2 #{primary}:#{dump_file}.bz2"
        execute << "rm -r /tmp/#{db_snapshot_name}.bz2"

        run_locally execute.join(" && ")
      end

      desc <<-DESC
        [internal] Imports the current database snapshot using drush.  On \
        rollback, the previous database will be imported.  This task is called by \
        the default deploy task, but can also be executed separately.
      DESC
      task :import, :roles => :web, :only => { :primary => true } do
        on_rollback do
          if previous_database
            run "cd #{previous_release}/drupal && bzcat #{previous_database} | drush sql-cli; true"
          else
            logger.important "no previous database to rollback to, rollback of database skipped"
          end
        end

        snapshot_name
        run "cd #{drupal_root} && bzcat #{current_database} | drush sql-cli"
      end

      desc "Dumps and imports the development database to the live site"
      task :default, :except => { :no_release => true } do
        dump
        import
      end
    end

    namespace :rollback do
      desc <<-DESC
        [internal] Points the current symlink at the previous revision, imports \
        the previous database snapshot, and unpacks the previous files directory. \
        This is called by the rollback sequence, and should rarely (if ever) need \
        to be called directly.
      DESC
      task :revision, :except => { :no_release => true } do
        if previous_release && previous_database && previous_files
          run "rm #{current_path}; ln -s #{previous_release}/drupal #{current_path}"
          run "cd #{previous_release}/drupal && bzcat #{previous_database} | drush sql-cli"
          files.rollback
        else
          abort "could not rollback the site because there is no prior release"
        end
      end

      desc <<-DESC
        [internal] Removes the most recently deployed release.  This is called by \
        the rollback sequence, and should rarely (if ever) need to be called directly.
      DESC
      task :cleanup, :except => { :no_release => true } do
        execute = []
        execute << "rm -rf #{current_release}"
        execute << "rm -f #{current_database}"
        execute << "rm -f #{current_files}"
        run "if [[ `readlink #{current_path}` != #{current_release}/drupal ]]; then #{execute.join(" && ")}; fi"
      end

      desc <<-DESC
        Rolls back to a previous version. This is handy if you ever \
        discover that you've deployed a lemon; `cap rollback' and you're right \
        back where you were, on the previously deployed version.
      DESC
      task :default do
        revision
        cleanup
      end
    end

    desc <<-DESC
      Pull the database and files directory from your primary server to your \
      secondary server.  Note that this wipes the current database and files \
      on your secondary server and completely replaces them with what is on \
      the primary machine.  Nothing that is created with these tasks is saved.
    DESC
    task :pull, :except => { :no_release => true } do
      db.pull.default
      files.pull.default
    end

    desc <<-DESC
      Clean up old releases. By default, the last 5 releases are kept on each \
      server (though you can change this with the keep_releases variable). All \
      other deployed revisions are removed from the servers. By default, this \
      will use sudo to clean up the old releases, but if sudo is not available \
      for your environment, set the :use_sudo variable to false instead.
    DESC
    task :cleanup, :except => { :no_release => true } do
      count = fetch(:keep_releases, 5).to_i
      if count >= releases.length
        logger.important "no old releases to clean up"
      else
        logger.info "keeping #{count} of #{releases.length} deployed releases"

        directories = (releases - releases.last(count)).map { |release|
          File.join(releases_path, release) }.join(" ")

        db_snapshots = (databases - databases.last(count)).map { |db_snapshot|
          File.join(databases_path, db_snapshot) }.join(" ")

        files_archives = (files_backup - files_backup.last(count)).map { |files_archive|
          File.join(files_backup_path, files_archive) }.join(" ")

        try_sudo "rm -rf #{directories} #{db_snapshots} #{files_archives}"
      end
    end

    desc <<-DESC
      Test deployment dependencies. Checks things like directory permissions, \
      necessary utilities, and so forth, reporting on the things that appear to \
      be incorrect or missing. This is good for making sure a deploy has a \
      chance of working before you actually run `cap deploy'.

      You can define your own dependencies, as well, using the `depend' method:

        depend :remote, :gem, "tzinfo", ">=0.3.3"
        depend :local, :command, "svn"
        depend :remote, :directory, "/u/depot/files"
    DESC
    task :check, :except => { :no_release => true } do
      dependencies = strategy.check!

      other = fetch(:dependencies, {})
      other.each do |location, types|
        types.each do |type, calls|
          if type == :gem
            dependencies.send(location).command(fetch(:gem_command, "gem")).or("`gem' command could not be found. Try setting :gem_command")
          end

          calls.each do |args|
            dependencies.send(location).send(type, *args)
          end
        end
      end

      if dependencies.pass?
        puts "You appear to have all necessary dependencies installed"
      else
        puts "The following dependencies failed. Please check them and try again:"
        dependencies.reject { |d| d.pass? }.each do |d|
          puts "--> #{d.message}"
        end
        abort
      end
    end

    namespace :pending do
      desc <<-DESC
        Displays the `diff' since your last deploy. This is useful if you want \
        to examine what changes are about to be deployed. Note that this might \
        not be supported on all SCM's.
      DESC
      task :diff, :except => { :no_release => true } do
        system(source.local.diff(current_revision))
      end

      desc <<-DESC
        Displays the commits since your last deploy. This is good for a summary \
        of the changes that have occurred since the last deploy. Note that this \
        might not be supported on all SCM's.
      DESC
      task :default, :except => { :no_release => true } do
        from = source.next_revision(current_revision)
        system(source.local.log(from))
      end
    end

  end

end # Capistrano::Configuration.instance(:must_exist).load do
