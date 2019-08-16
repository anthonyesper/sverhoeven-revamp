#!/bin/bash

export CARTO_HOSTNAME=${CARTO_HOSTNAME:=$HOSTNAME}

perl -pi -e 's/cartodb\.localhost/$ENV{"CARTO_HOSTNAME"}/g' /etc/nginx/nginx.conf /cartodb/config/app_config.yml /Windshaft-cartodb/config/environments/development.js

PGDATA=/var/lib/postgresql
if [ "$(stat -c %U $PGDATA)" != "postgres" ]; then
(>&2 echo "${PGDATA} not owned by postgres, updating permissions")
chown -R postgres $PGDATA
chmod 700 $PGDATA
fi

service postgresql start
service redis-server start
/opt/varnish/sbin/varnishd -a :6081 -T localhost:6082 -s malloc,256m -f /etc/varnish.vcl
service nginx start

cd /Windshaft-cartodb
node app.js development &

cd /CartoDB-SQL-API
node app.js development &

cd /cartodb
bundle exec script/restore_redis
bundle exec script/resque > resque.log 2>&1 &
script/sync_tables_trigger.sh &

# Recreate api keys in db and redis, so sql api is authenticated
echo 'delete from api_keys' | psql -U postgres -t carto_db_development
bundle exec rake carto:api_key:create_default

#FORCING HTTPS IN DEV 
echo "Changing the self.use_https? method in /cartodb/config/initializers/carto_db.rb to return true, so https works in dev."
sed -i "/def self.use_https\?/,/end/c\  def self.use_https?\n    true\n  end" /cartodb/config/initializers/carto_db.rb
sed -i 's|http://|https://|g' /Windshaft-cartodb/config/environments/development.js


# bundle exec rake carto:api_key:create_default
bundle exec thin start --threaded -p 3000 --threadpool-size 5
