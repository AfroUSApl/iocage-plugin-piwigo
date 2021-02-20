# iocage-plugin-piwigo

This is iocage plugin to create Piwigo, an open source photo gallery software for the web. Designed for organisations, teams and individuals.
More details at http://piwigo.org

I have tested this plugin couple of times on my TrueNAS 12.2 as a 12.2-RELEASE and 11.4-RELEASE, all seems to work well.

Please remember to read info in TrueNAS / Plugins / Piwigo / POST INSTALL NOTES - to access info with DB user and DB password.
Piwigo first installation page will set Host: as localhost, usually this needs to be changed to 127.0.0.1
   Host: 127.0.0.1
Second tip is to set your own date and time location in PHP.INI, as for this installation I have chosen Europe/London ;)

Some of the post installation settings I have tuned for:

# This is an <h1> tag
## This is an <h2> tag
###### This is an <h6> tag

######PHP
<h6>    date.timezone = "Europe/London"
<h6>    max_execution_time = 300
<h6>    max_input_time = 300
<h6>    post_max_size = 100M
<h6>    upload_max_filesize = 100M
<h6>    memory_limit = 512M

######Nginx
<h6>    proxy_connect_timeout 600s
<h6>    proxy_send_timeout 600s
<h6>    proxy_read_timeout 600s
<h6>    fastcgi_send_timeout 600s
<h6>    fastcgi_read_timeout 600s

<h6>    pm.max_children = 35
<h6>    pm.start_servers = 15
<h6>    pm.min_spare_servers = 15
<h6>    pm.max_spare_servers = 20

<h6>    request_terminate_timeout = 300
