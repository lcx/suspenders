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
empty_directory "app/views/users"
copy_file "_flashes.html.erb", "app/views/shared/_flashes.html.erb"
copy_file "_javascript.html.erb", "app/views/shared/_javascript.html.erb"
copy_file "user_session_new.html.erb", "app/views/user_sessions/new.html.erb"
copy_file "user_form.html.erb", "app/views/users/_user.html.erb"
copy_file "user_view.html.erb", "app/views/users/new.html.erb"
copy_file "user_view.html.erb", "app/views/users/edit.html.erb"


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
generate "controller UserSessions"
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
  
  def is_admin
    if current_user.is_admin?
    else
      flash[:error]="You don't have permission to do this"
      redirect_to root_url
    end
  end  
RUBY
inject_into_class "app/controllers/application_controller.rb", "ApplicationController", app_controller

user_session_controller = <<-RUBY
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => :destroy

  def new
    @user_session = UserSession.new
  end

  def create
    @user_session = UserSession.new(params[:user_session])
    if @user_session.save
      flash[:notice] = t("Login successful!")
      redirect_back_or_default users_url
    else
      render :action => :new
    end
  end

  def destroy
    current_user_session.destroy
    flash[:notice] = t("Logout successful!")
    redirect_back_or_default new_user_session_url
  end
RUBY

user_controller = <<-RUBY
  before_filter :require_user, :except=>[:new,:create]
  def new
	@user = User.new
  end

  def create
	@user = User.new(params[:user])
	if @user.save
	  flash[:notice] = t("Registration successful.")
	  redirect_to root_url
	else
	  render :action => 'new'
	end
  end

  def edit
	# ==============================================================================================================================
	# = if it's an admin, load the user from the params else use currentuser, this prevents users from forging other user accounts =
	# ==============================================================================================================================
	if (current_user.is_admin?) && (params[:id]!="current")
	  @user=User.find(params[:id])
	else
	  @user = current_user
	end
  end

  def update
	# ==============================================================================================================================
	# = if it's an admin, load the user from the params else use currentuser, this prevents users from forging other user accounts =
	# ==============================================================================================================================
	if current_user.is_admin?
	  @user=User.find(params[:id])
	else
	  @user = current_user
	end
	if @user.update_attributes(params[:user])
	  flash[:notice] = t("Successfully updated profile.")
	  redirect_to root_url
	else
	  render :action => 'edit'
	end
  end

  def index
	if current_user.is_admin?
	  @users=User.all
	else
	  redirect_to root_url
	end
  end
RUBY

inject_into_class "app/controllers/user_sessions_controller.rb", "UserSessionsController", user_session_controller
generate "controller users"
#create_file "app/controllers/users_controller.rb"
inject_into_class "app/controllers/users_controller.rb", "UsersController", user_controller

#generate "clearance:install"
#generate "clearance:features"

#create_file "public/stylesheets/sass/screen.scss"
create_file "public/stylesheets/screen.css"
copy_file "screen.scss", "public/stylesheets/sass/screen.scss"

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

route "resources :user_sessions"
route "resources :users"
route "root :to => 'user_sessions#new'"
route "match 'login' => \"user_sessions#new\",      :as => :login"
route "match 'logout' => \"user_sessions#destroy\", :as => :logout"
run "touch public/stylesheets/sass/screen.scss"

say "Congratulations! You just pulled our suspenders."
say "Remember to run 'rails generate hoptoad' with your API key."

