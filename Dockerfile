FROM ppc64le/ubuntu:16.04
MAINTAINER Edwin Wang <edwin@oohoo.org>

RUN apt-get update

LABEL install basic package
RUN apt-get install vim apt-utils -y
RUN apt-get install -y \
    build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libre2-dev \
    libreadline-dev libncurses5-dev libffi-dev curl openssh-server libxml2-dev \
    checkinstall libxslt-dev libcurl4-openssl-dev libicu-dev logrotate \
    python-docutils pkg-config cmake hostname

LABEL install git
RUN apt-get install -y libcurl4-openssl-dev libexpat1-dev gettext libz-dev
RUN curl --remote-name --progress \
    https://www.kernel.org/pub/software/scm/git/git-2.8.4.tar.gz
RUN echo '626e319f8a24fc0866167ea5f6bf3e2f38f69d6cb2e59e150f13709ca3ebf301  git-2.8.4.tar.gz' \
    | shasum -a256 -c - && tar -xzf git-2.8.4.tar.gz
RUN cd git-2.8.4 && ./configure && make prefix=/usr/local all \
    && make prefix=/usr/local install
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y postfix
# CMD /etc/init.d/postfix start && /bin/bash

LABEL install ruby
RUN curl --remote-name --progress \
    https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.3.tar.gz
RUN echo '1014ee699071aa2ddd501907d18cbe15399c997d  ruby-2.3.3.tar.gz' \
    | shasum -c - && tar xzf ruby-2.3.3.tar.gz
RUN cd ruby-2.3.3 && ./configure --disable-install-rdoc && make && make install
RUN gem install bundler --no-ri --no-rdoc

LABEL install go
RUN rm -rf /usr/local/go
RUN curl --remote-name --progress \
    https://storage.googleapis.com/golang/go1.8.3.linux-ppc64le.tar.gz
RUN echo '3ef38d31d6afbafa2d6d1e02e5c7e690528c035f  go1.8.3.linux-ppc64le.tar.gz' \
    | shasum -a256 -c - && tar -C /usr/local -xzf go1.8.3.linux-ppc64le.tar.gz
RUN ln -sf /usr/local/go/bin/go /usr/local/bin/
RUN ln -sf /usr/local/go/bin/godoc /usr/local/bin/
RUN ln -sf /usr/local/go/bin/gofmt /usr/local/bin/

LABEL install node.js
RUN curl --remote-name --progress \
    https://nodejs.org/dist/v6.11.3/node-v6.11.3-linux-ppc64le.tar.xz
RUN tar -C /usr/local -xf node-v6.11.3-linux-ppc64le.tar.xz
RUN mv /usr/local/node-v6.11.3-linux-ppc64le /usr/local/node
RUN ln -sf /usr/local/node/bin/node /usr/local/bin
RUN ln -sf /usr/local/node/bin/npm /usr/local/bin
RUN npm install --global yarn
RUN ln -sf /usr/local/node/bin/yarn /usr/local/bin
RUN ln -sf /usr/local/node/bin/yarnpkg /usr/local/bin

LABEL add user
RUN adduser --disabled-login --gecos 'GitLab' git

LABEL install database
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql \
    postgresql-client libpq-dev postgresql-contrib sudo
RUN sed -e "s/[#]\?listen_addresses = .*/listen_addresses = '*'/g" \
    -i '/etc/postgresql/9.5/main/postgresql.conf'
RUN echo "host all all 0.0.0.0/0 trust" >> '/etc/postgresql/9.5/main/pg_hba.conf'
RUN echo "local all all trust" >> '/etc/postgresql/9.5/main/pg_hba.conf'
RUN service postgresql start && sleep 60 && \
    sudo -u postgres psql -d template1 -c "CREATE USER git CREATEDB;" && \
    sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" && \
    sudo -u postgres psql -d template1 -c "CREATE DATABASE gitlabhq_production OWNER git;"

LABEL install redis
RUN apt-get install -y redis-server
RUN cp /etc/redis/redis.conf /etc/redis/redis.conf.orig
RUN sed 's/^port .*/port 0/' /etc/redis/redis.conf.orig \
    | tee /etc/redis/redis.conf
RUN echo 'unixsocket /var/run/redis/redis.sock' | tee -a /etc/redis/redis.conf
RUN echo 'unixsocketperm 770' | tee -a /etc/redis/redis.conf
RUN mkdir /var/run/redis -p
RUN chown redis:redis /var/run/redis
RUN chmod 755 /var/run/redis
RUN mkdir /etc/tmpfiles.d -p && echo \
    'd  /var/run/redis  0755  redis  redis  10d  -' \
    | tee -a /etc/tmpfiles.d/redis.conf
#RUN service redis-server restart
RUN usermod -aG redis git

LABEL install GitLab
RUN cd /home/git && sudo -u git -H git clone \
    https://gitlab.com/gitlab-org/gitlab-ce.git -b 10-0-stable gitlab
WORKDIR /home/git/gitlab
RUN sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml
RUN sed -e "s/\/usr\/bin\/git/\/usr\/local\/bin\/git/g" -i config/gitlab.yml
RUN sudo -u git -H cp config/secrets.yml.example config/secrets.yml
RUN sudo -u git -H chmod 0600 config/secrets.yml
RUN chown -R git log/
RUN chown -R git tmp/
RUN chmod -R u+rwX,go-w log/
RUN chmod -R u+rwX tmp/
RUN chmod -R u+rwX tmp/pids/
RUN chmod -R u+rwX tmp/sockets/
RUN sudo -u git -H mkdir public/uploads/
RUN chmod 0700 public/uploads
RUN chmod -R u+rwX builds/
RUN chmod -R u+rwX shared/artifacts/
RUN chmod -R ug+rwX shared/pages/
RUN sudo -u git -H cp config/unicorn.rb.example config/unicorn.rb
RUN sudo -u git -H cp config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb
RUN sudo -u git -H git config --global core.autocrlf input
RUN sudo -u git -H git config --global gc.auto 0
RUN sudo -u git -H git config --global repack.writeBitmaps true
RUN sudo -u git -H cp config/resque.yml.example config/resque.yml
RUN sudo -u git cp config/database.yml.postgresql config/database.yml
RUN sudo -u git -H chmod o-rwx config/database.yml
RUN sudo -u git -H bundle install --deployment --without development test mysql aws kerberos
RUN sudo -u git -H bundle exec rake gitlab:shell:install REDIS_URL=unix:/var/run/redis/redis.sock RAILS_ENV=production SKIP_STORAGE_VALIDATION=true
RUN sudo -u git -H bundle exec rake "gitlab:workhorse:install[/home/git/gitlab-workhorse]" RAILS_ENV=production
RUN service postgresql start && service redis-server start && sleep 60 \
    && sudo -u postgres psql -c "UPDATE pg_database SET datistemplate = FALSE WHERE datname = 'template1';" \
    && sudo -u postgres psql -c "DROP DATABASE template1;" \
    && sudo -u postgres psql -c "CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UNICODE';" \
    && sudo -u postgres psql -c "UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'template1';" \
    && sudo -u postgres psql -d template1 -c " VACUUM FREEZE;" \
    && sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" \
    && yes yes | sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production


RUN cp lib/support/init.d/gitlab /etc/init.d/gitlab
#??? sudo cp lib/support/init.d/gitlab.default.example /etc/default/gitlab
RUN update-rc.d gitlab defaults 21
RUN sudo -u git -H bundle exec rake "gitlab:gitaly:install[/home/git/gitaly]" RAILS_ENV=production
RUN chmod 0700 /home/git/gitlab/tmp/sockets/private
RUN chown git /home/git/gitlab/tmp/sockets/private
RUN cp lib/support/logrotate/gitlab /etc/logrotate.d/gitlab
RUN service postgresql start && service redis-server start && sleep 60 \
    && sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production
RUN sudo -u git -H bundle exec rake gettext:pack RAILS_ENV=production
RUN sudo -u git -H bundle exec rake gettext:po_to_json RAILS_ENV=production
RUN sudo -u git -H yarn install --production --pure-lockfile
RUN sudo -u git -H bundle exec rake gitlab:assets:compile RAILS_ENV=production NODE_ENV=production
RUN service postgresql start && service redis-server start && sleep 60 \
    && service gitlab restart

LABEL install nginx
RUN apt-get install -y nginx
RUN cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
RUN ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
RUN rm /etc/nginx/sites-enabled/default
RUN sed -i '28,53 s/^/# /gm' /etc/nginx/sites-enabled/gitlab
RUN sed -i '82 s/ gitlab_access//g' /etc/nginx/sites-enabled/gitlab
RUN nginx -t
CMD /usr/sbin/nginx

LABEL fix before check
RUN chmod -R ug+rwX,o-rwx /home/git/repositories
RUN chmod -R ug-s /home/git/repositories
RUN find /home/git/repositories -type d -print0 | xargs -0 chmod g+s
RUN mkdir ~/gitlab-check-backup-1505496178
RUN mv /home/git/.ssh/environment ~/gitlab-check-backup-1505496178

LABEL check environment
RUN service postgresql start && service redis-server start && sleep 60 \
    && sudo -u git -H bundle exec rake gitlab:check RAILS_ENV=production

# EXPOSE 443 80 22

WORKDIR /
COPY wrapper.sh wrapper.sh
ENTRYPOINT bash ./wrapper.sh

