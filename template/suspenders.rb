# Suspenders
# =============
# by thoughtbot

require 'net/http'
require 'net/https'

template_root = File.expand_path(File.join(File.dirname(__FILE__)))
source_paths << File.join(template_root, "files")

# Helpers

def concat_file(source, destination)
  contents = IO.read(find_in_source_paths(source))
  append_file destination, contents
end

def replace_in_file(relative_path, find, replace)
  path = File.join(destination_root, relative_path)
  contents = IO.read(path)
  unless contents.gsub!(find, replace)
    raise "#{find.inspect} not found in #{relative_path}"
  end
  File.open(path, "w") { |file| file.write(contents) }
end

def action_mailer_host(rails_env, host)
  inject_into_file(
    "config/environments/#{rails_env}.rb",
    "\n\n  config.action_mailer.default_url_options = { :host => '#{host}' }",
    :before => "\nend"
  )
end

def download_file(uri_string, destination)
  uri = URI.parse(uri_string)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true if uri_string =~ /^https/
  request = Net::HTTP::Get.new(uri.path)
  contents = http.request(request).body
  path = File.join(destination_root, destination)
  File.open(path, "w") { |file| file.write(contents) }
end

def origin
  if ENV['REPO'].present?
    ENV['REPO']
  else
    "git://github.com/lcx/suspenders.git"
  end
end

def trout(destination_path)
  run "trout checkout --source-root=template/trout #{destination_path} #{origin}"
end

say "Getting rid of files we don't use"

remove_file "README"
remove_file "public/index.html"
remove_file "public/images/rails.png"

say "Setting up the staging environment"

run "cp config/environments/production.rb config/environments/staging.rb"

say "Creating suspenders views"

empty_directory "app/views/shared"
copy_file "_flashes.html.erb", "app/views/shared/_flashes.html.erb"
copy_file "_javascript.html.erb", "app/views/shared/_javascript.html.erb"
template "suspenders_layout.html.erb.erb",
         "app/views/layouts/application.html.erb",
         :force => true

trout 'Gemfile'
run "bundle install"

say "Let's use jQuery"
generate "jquery:install", "--ui"

say "Pulling in some common javascripts"

trout "public/javascripts/prefilled_input.js"

say "Documentation"

copy_file "README_FOR_SUSPENDERS", "doc/README_FOR_SUSPENDERS"

say "Get ready for bundler... (this will take a while)"

say "Let's use MySQL"

template "mysql_database.yml.erb", "config/database.yml", :force => true
rake "db:create"

say "Setting up plugins"

generators_config = <<-RUBY
    config.generators do |generate|
      generate.test_framework :rspec
    end
RUBY
inject_into_class "config/application.rb", "Application", generators_config

action_mailer_host "development", "#{app_name}.local"
action_mailer_host "test",        "example.com"
action_mailer_host "staging",     "staging.#{app_name}.com"
action_mailer_host "production",  "#{app_name}.com"

generate "rspec:install"
generate "cucumber:install", "--rspec --capybara"
generate "authlogic:session UserSession"
copy_file "user.rb", "app/models/user.rb"
copy_file "create_users.rb", "db/migrate/#{Time.now.strftime("%Y%m%d%H%M%S")}_create_users.rb"

app_controller = <<-RUBY
  filter_parameter_logging :password

  helper_method :current_user_session, :current_user

  private

  def current_user_session
    logger.debug "ApplicationController::current_user_session"
    return @current_user_session if defined?(@current_user_session)
    @current_user_session = UserSession.find
  end

  def current_user
    logger.debug "ApplicationController::current_user"
    return @current_user if defined?(@current_user)
    @current_user = current_user_session && current_user_session.user
  end

  def require_user
    logger.debug "ApplicationController::require_user"
    unless current_user
      store_location
      flash[:notice] = t("You must be logged in to access this page")
      redirect_to new_user_session_url
      return false
    end
  end

  def require_no_user
    logger.debug "ApplicationController::require_no_user"
    if current_user
      store_location
      flash[:notice] = t("You must be logged out to access this page")
      redirect_to account_url
      return false
    end
  end

  def store_location
    session[:return_to] = request.request_uri
  end

  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end
RUBY
inject_into_class "app/controllers/application_controller.rb", "ApplicationController", app_controller
#generate "clearance:install"
#generate "clearance:features"

#create_file "public/stylesheets/sass/screen.scss"
copy_file "screen.scss", "public/stylesheets/sass/screen.scss"
create_file "public/stylesheets/screen.css"

copy_file "factory_girl_steps.rb", "features/step_definitions/factory_girl_steps.rb"

replace_in_file "spec/spec_helper.rb", "mock_with :rspec", "mock_with :mocha"

inject_into_file "features/support/env.rb",
                 %{Capybara.save_and_open_page_path = 'tmp'\n} +
                 %{Capybara.javascript_driver = :webkit\n},
                 :before => %{Capybara.default_selector = :css}

rake "flutie:install"

say "Ignore the right files"

concat_file "suspenders_gitignore", ".gitignore"
concat_file "cucumber_assertions_hack", "features/support/env.rb"

["app/models",
 "app/views/pages",
 "db/migrate",
 "log",
 "public/images",
 "spec/support",
 "spec/lib",
 "spec/models",
 "spec/views",
 "spec/controllers",
 "spec/helpers",
 "spec/support/matchers",
 "spec/support/mixins",
 "spec/support/shared_examples"].each do |dir|
  empty_directory_with_gitkeep dir
end

say "Copying miscellaneous support files"

copy_file "errors.rb", "config/initializers/errors.rb"
copy_file "time_formats.rb", "config/initializers/time_formats.rb"
copy_file "body_class_helper.rb", "app/helpers/body_class_helper.rb"


say "Setting up a root route"

route "root :to => 'Clearance::Sessions#new'"
# match 'login' => "user_sessions#new",      :as => :login
#   match 'logout' => "user_sessions#destroy", :as => :logout

# map.login 'login', :controller => 'user_sessions', :action => 'new'
# map.logout 'logout', :controller => 'user_sessions', :action => 'destroy'


say "Congratulations! You just pulled our suspenders."
say "Remember to run 'rails generate hoptoad' with your API key."

