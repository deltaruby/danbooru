set :user, "danbooru"
set :rails_env, "production"
server "danbooru_test.rnn", :roles => %w(web app db), :primary => true, :user => "danbooru"
#server "hijiribe.donmai.us", :roles => %w(web app), :user => "albert"
