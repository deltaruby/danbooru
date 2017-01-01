set :user, "deltaruby"
set :rails_env, "production"
server "danbooru.deltaruby", :roles => %w(web app db), :primary => true, :user => "deltaruby"
#server "hijiribe.donmai.us", :roles => %w(web app), :user => "albert"
