#!/usr/bin/env perl
## --------------------------------------------------------------------------------------------------------------------

use Modern::Perl;
use Config::Simple;
use File::Slurp;
use File::Temp ();
use IPC::Run3;
use Cwd qw();
use File::Basename qw();
use JSON::Any;

## --------------------------------------------------------------------------------------------------------------------

title("The Deployer is Deploying - Stand Back!");

# check we can get sudo
run("sudo echo");

## --------------------------------------------------------------------------------------------------------------------
# Always update the code first, since `deployer/settings` or `deployer/env` need to be read after an update.

sep();
title("Updating the Code");
run('git fetch --verbose');
run('git rebase');

## --------------------------------------------------------------------------------------------------------------------
# Setup

sep();
title("Running Setup");

# You wouldn't do this normally since it depends on an ENV var, instead use User or File::HomeDir,
my $username = $ENV{USER};

my $dir = Cwd::cwd();
my ($name) = File::Basename::fileparse($dir);
my $safe_name = $name;
$safe_name =~ s/\./-/g;

my $is_node     = 0;
my $is_golang   = 0;
my $is_nebulous = 0;
if ( -f 'package.json' || -f 'package-lock.json' ) {
    my $start = `jq -r '.dependencies."nebulous-server"' package.json`;
    chomp $start;
    if ( defined $start && $start ne 'null' ) {
        $is_nebulous = 1;
    }
    else {
        $is_node = 1;
    }
}
if ( -f 'vendor/manifest' ) {
    $is_golang = 1;
}

# figure out Nginx
my $is_nginx_certbot = 0;
my $is_nginx_origin_certificate = 0;
my $is_nginx_tailscale = 0;
my $is_nginx_done = 0;
if ( -f "deployer/nginx-certbot" ) {
    $is_nginx_certbot = 1;
}
elsif ( -f "deployer/nginx-origin-certificate" ) {
    $is_nginx_origin_certificate = 1;
}
elsif ( -f "deployer/nginx-tailscale" ) {
    $is_nginx_tailscale = 1;
}
else {
    # nothing to do here
}

my $setting = {};
my $settings = new Config::Simple('deployer/settings');
if ( defined $settings ) {
    %$setting = $settings->vars();
}
my $apex = $setting->{apex};
my $port = $setting->{port};
my $www = defined $setting->{www} ? ($setting->{www}+0) : 1; # default: add the `www.$apex` server
my $cmd = $setting->{cmd};

my $env = {};
if ( -f 'deployer/env' ) {
    my $cfg = new Config::Simple('deployer/env');
    if ( defined $cfg ) {
        %$env = $cfg->vars();
    }
}

msg("User         : $ENV{USER}");
msg("Current Dir  : $dir");
msg("Name         : $name");
msg("Safe Name    : $safe_name");
msg("Is Node.js?  : $is_node");
msg("Is GoLang?   : $is_golang");
msg("Is Nebulous? : $is_nebulous");
msg("Settings     :");
msg(" - apex=$apex");
msg(" - port=$port");
msg(" - www=$www");
msg(" - cmd=" . ($cmd || ''));
msg("Env          :");
while (my ($k, $v) = each(%$env)) {
    msg(" - $k=$v");
    if ($v eq "?") {
        # firstly, see if a `deployer/ENV_$k` file exists
        my $filename = "deployer/ENV_$k";
        if ( -f $filename ) {
            my $value = read_file($filename);
            chomp $value;
            $env->{$k} = $value;
        }
        else {
            print " Value? - $k=";
            my $value = <STDIN>;
            chomp $value;
            $env->{$k} = $value;
            write_file($filename, $value);
        }
        msg(" - $k=$env->{$k}");
    }
}

## --------------------------------------------------------------------------------------------------------------------
# Packages

sep();
title("Checking Packages");

if ( -f 'deployer/packages' ) {
    my @pkgs = read_file('deployer/packages');
    chomp @pkgs;
    for my $pkg ( @pkgs ) {
        run("apt policy $pkg");
    }
}
else {
    msg("No 'packages' file.");
}

## --------------------------------------------------------------------------------------------------------------------
# Update Packages

# if ( $is_node ) {
#     sep();
#     title("Installing NPM Packages");
#     run('npm ci');
#     run('npm run build');
#     run('npm ci --production');
# }
if ( $is_golang ) {
    sep();
    title("Building GoLang");
    run('gb build');
}
if ( $is_nebulous ) {
    sep();
    title("Installing NPM Packages");
    run('npm ci');
}

## --------------------------------------------------------------------------------------------------------------------
# Make

sep();
title("Making the Project");
if ( -f "Makefile" ) {
    run("make");
}
else {
    msg("No Makefile found");
}

## --------------------------------------------------------------------------------------------------------------------
# Minify

sep();
title("Minifying Assets");
if ( -f "deployer/minify" ) {
    my @minifies = read_file('deployer/minify');
    chomp @minifies;
    for my $minify ( @minifies ) {
        my ($type, $filename) = split(':', $minify);
        if ( $type eq 'css' ) {
            msg("Minifying CSS : $filename.css");
            run("curl -X POST -s --data-urlencode 'input\@$filename.css' https://cssminifier.com/raw > $filename.min.css");
        }
        if ( $type eq 'js' ) {
            msg("Minifying JavaScript : $filename.js");
            run("curl -X POST -s --data-urlencode 'input\@$filename.js' https://javascript-minifier.com/raw > $filename.min.js");
        }
        if ( $type eq 'png' ) {
            msg("Crushing PNG : $filename.png");
            run("curl -X POST -s --form 'input=\@filename.png;type=image/png' https://pngcrush.com/crush > $filename.min.png");
        }
        if ( $type eq 'jpg' ) {
            msg("Optimising JPG : $filename.jpg");
            run("curl -X POST -s --form 'input=\@filename.jpg;type=image/jpg' https://jpgoptimiser.com/optimise > $filename.min.jpg");
        }
    }
}
else {
    msg("No minify file found");
}

## --------------------------------------------------------------------------------------------------------------------
# Dirs

sep();
title("Creating Dirs");

if ( -f "deployer/dirs" ) {
    my @dirs = read_file('deployer/dirs');
    chomp @dirs;
    for my $line ( @dirs ) {
        run("sudo mkdir -p $line");
        run("sudo chown $username.$username $line");
    }
}
else {
    msg("No dirs file found");
}

## --------------------------------------------------------------------------------------------------------------------
# Cron

sep();
title("Cron");

if ( -f "deployer/cron.d" ) {
    run("sudo cp deployer/cron.d /etc/cron.d/$safe_name");
}
else {
    msg("No cron.d file found");
}

## --------------------------------------------------------------------------------------------------------------------
# Supervisor

sep();
title("Supervisor");

if ( -f "deployer/supervisor" ) {
    # for supervisord logging
    run("sudo mkdir -p /var/log/$name/");

    # create each line of the supervisor file
    my @supervisor;

    # create each line
    push(@supervisor, "[program:$safe_name]\n");
    push(@supervisor, "directory = $dir\n");
    if ( $cmd ) {
        push(@supervisor, "command = $cmd\n");
    }
    elsif ( $is_node ) {
        push(@supervisor, "command = node server.js\n");
    }
    elsif ( $is_nebulous ) {
        push(@supervisor, "command = npm start\n");
    }
    else {
        push(@supervisor, "command = echo 'Error: Unknown deployer command.'\n");
    }
    push(@supervisor, "user = $username\n");
    push(@supervisor, "autostart = true\n");
    push(@supervisor, "autorestart = true\n");
    push(@supervisor, "start_retries = 3\n");
    push(@supervisor, "stdout_logfile = /var/log/$name/stdout.log\n");
    push(@supervisor, "stdout_logfile_maxbytes = 50MB\n");
    push(@supervisor, "stdout_logfile_backups = 20\n");
    push(@supervisor, "stderr_logfile = /var/log/$name/stderr.log\n");
    push(@supervisor, "stderr_logfile_maxbytes = 50MB\n");
    push(@supervisor, "stderr_logfile_backups = 20\n");

    # environment
    push(@supervisor, "environment = APEX=\"$apex\",PORT=\"$port\"");
    if ( $is_node || $is_nebulous ) {
        push(@supervisor, ",NODE_ENV=\"production\"");
    }
    # copy all ENV VARS over
    while (my ($k, $v) = each(%$env)) {
        push(@supervisor, ",$k=\"$v\"");
    }
    push(@supervisor, "\n");

    # write this out to a file
    my $supervisor_fh = File::Temp->new();
    my $supervisor_filename = $supervisor_fh->filename;

    msg("Writing $supervisor_filename");
    msg(@supervisor);
    write_file($supervisor_fh, @supervisor);

    run("sudo cp $supervisor_filename /etc/supervisor/conf.d/$name.conf");

    run("sudo supervisorctl restart $safe_name");

}
else {
    msg("No supervisor file found");
}

## --------------------------------------------------------------------------------------------------------------------
# Origin Certificate

sep();
title("Origin Certificate");

if ( $is_nginx_origin_certificate ) {
    # check we have all the files
    # ( -f "deployer/key.age" ) <- no longer needed!
    if ( -f "deployer/key.age" && -f "deployer/apex.pem" && -f "deployer/apex.key.age" ) {
        msg("It looks like you have all files of an Origin Certificate from Cloudflare.");
        msg("");
        msg("Copying 'apex.pem' to '/etc/ssl/$apex.pem'");
        run("sudo cp deployer/apex.pem /etc/ssl/$apex.pem");
        msg("");
        msg("Decrypting 'apex.key.age' to 'apex.key");
        run("age --decrypt --identity=deployer/key.age --output=deployer/apex.key deployer/apex.key.age");
        msg("");
        msg("Copying 'apex.key' to '/etc/ssl/private/$apex.key");
        run("sudo cp deployer/apex.key /etc/ssl/private/$apex.key");
        msg("");
        msg("Fixing ownership and permissions on '/etc/ssl/private/$apex.key");
        run("sudo chown root.ssl-cert /etc/ssl/private/$apex.key");
        run("sudo chmod 640 /etc/ssl/private/$apex.key");
        msg("");
        msg("Removing 'apex.key'");
        run("rm deployer/apex.key");
    }
    else {
        msg("Missing file(s) for Nginx Origin Certificate: key.age, apex.key.age, apex.pem");
    }
}
else {
    msg("No Origin Certificate configured.");
}

## --------------------------------------------------------------------------------------------------------------------
# Nginx

sep();
title("Nginx (CertBot, Origin Certificate, Tailscale)");

# Firstly we need to figure out if we are doing an Origin Cert (from Cloudflare)
# using CertBot (the default).

if ( $is_nginx_certbot ) {
    msg("Nginx with CertBot");

    # Skip if the Nginx config already exists.
    if ( ! -f "/etc/nginx/sites-available/$name.conf" ) {
        my @nginx;
        push(@nginx, "server {\n");
        push(@nginx, "    listen      80;\n");
        push(@nginx, "    server_name $apex;\n");
        push(@nginx, "    location    / {\n");
        push(@nginx, "        proxy_set_header   X-Real-IP           \$remote_addr;\n");
        push(@nginx, "        proxy_set_header   X-Forwarded-For     \$proxy_add_x_forwarded_for;\n");
        # chilts@zool:~$ sudo nginx -t
        # nginx: [emerg] unknown "proxy_x_forwarded_proto" variable
        # nginx: configuration file /etc/nginx/nginx.conf test failed
        # push(@nginx, "        proxy_set_header   X-Forwarded-Proto   \$proxy_x_forwarded_proto;\n");
        push(@nginx, "        proxy_set_header   Host                \$http_host;\n");
        push(@nginx, "        proxy_pass         http://localhost:$port;\n");
        push(@nginx, "    }\n");
        push(@nginx, "}\n");
        push(@nginx, "\n");

        if ( $www ) {
            push(@nginx, "server {\n");
            push(@nginx, "    listen      80;\n");
            push(@nginx, "    server_name www.$apex;\n");
            push(@nginx, "    return      301 \$scheme://$apex\$request_uri;\n");
            push(@nginx, "}\n");
        }

        # write this out to a file
        my $nginx_fh = File::Temp->new();
        my $nginx_filename = $nginx_fh->filename;

        msg("Writing $nginx_filename");
        msg(@nginx);
        write_file($nginx_fh, @nginx);

        run("sudo cp $nginx_filename /etc/nginx/sites-available/$apex.conf");

        # only do the symlink if it doesn't already exist
        if ( ! -l "/etc/nginx/sites-enabled/$apex.conf" ) {
            run("sudo ln -s /etc/nginx/sites-available/$apex.conf /etc/nginx/sites-enabled/$apex.conf");
        }

        # restart Nginx
        run("sudo service nginx restart");
    }
    else {
        $is_nginx_done = 1;
        msg("Nginx config already set up. You'll need to make changes manually to force any changes.");
    }
}
elsif ( $is_nginx_origin_certificate ) {
    msg("Nginx with Origin Certificate from Cloudflare");

    # Four configs:
    # 1. secure apex
    # 2. plaintext apex
    # 3. secure www
    # 4. plaintext www

    my @nginx;

    push(@nginx, "server {\n");
    push(@nginx, "    listen              443;\n");
    push(@nginx, "    server_name         $apex;\n");
    push(@nginx, "    ssl                 on;\n");
    push(@nginx, "    ssl_certificate     /etc/ssl/$apex.pem;\n");
    push(@nginx, "    ssl_certificate_key /etc/ssl/private/$apex.key;\n");
    push(@nginx, "    location            / {\n");
    push(@nginx, "        proxy_set_header    X-Real-IP           \$remote_addr;\n");
    push(@nginx, "        proxy_set_header    X-Forwarded-For     \$proxy_add_x_forwarded_for;\n");
    # chilts@zool:~$ sudo nginx -t
    # nginx: [emerg] unknown "proxy_x_forwarded_proto" variable
    # nginx: configuration file /etc/nginx/nginx.conf test failed
    # push(@nginx, "        proxy_set_header   X-Forwarded-Proto   \$proxy_x_forwarded_proto;\n");
    push(@nginx, "        proxy_set_header    Host                \$http_host;\n");
    push(@nginx, "        proxy_pass          http://localhost:$port;\n");
    push(@nginx, "    }\n");
    push(@nginx, "    access_log          /var/log/nginx/$apex.access.log;\n");
    push(@nginx, "    error_log           /var/log/nginx/$apex.error.log;\n");
    push(@nginx, "}\n");
    push(@nginx, "\n");

    push(@nginx, "server {\n");
    push(@nginx, "    listen              80;\n");
    push(@nginx, "    server_name         $apex;\n");
    push(@nginx, "    access_log          /var/log/nginx/$apex.access.log;\n");
    push(@nginx, "    error_log           /var/log/nginx/$apex.error.log;\n");
    push(@nginx, "    return              301 https://$apex\$request_uri;\n");
    push(@nginx, "}\n");
    push(@nginx, "\n");

    if ( $www ) {
        push(@nginx, "server {\n");
        push(@nginx, "    listen              443;\n");
        push(@nginx, "    server_name         www.$apex;\n");
        push(@nginx, "    ssl                 on;\n");
        push(@nginx, "    ssl_certificate     /etc/ssl/$apex.pem;\n");
        push(@nginx, "    ssl_certificate_key /etc/ssl/private/$apex.key;\n");
        push(@nginx, "    access_log          /var/log/nginx/$apex-www.access.log;\n");
        push(@nginx, "    error_log           /var/log/nginx/$apex-www.error.log;\n");
        push(@nginx, "    return 301          https://$apex\$request_uri;\n");
        push(@nginx, "}\n");
        push(@nginx, "\n");

        push(@nginx, "server {\n");
        push(@nginx, "    listen              80;\n");
        push(@nginx, "    server_name         www.$apex;\n");
        push(@nginx, "    access_log          /var/log/nginx/$apex-www.access.log;\n");
        push(@nginx, "    error_log           /var/log/nginx/$apex-www.error.log;\n");
        push(@nginx, "    return              301 https://$apex\$request_uri;\n");
        push(@nginx, "}\n");
    }

    # write this out to a file
    my $nginx_fh = File::Temp->new();
    my $nginx_filename = $nginx_fh->filename;

    msg("Writing $nginx_filename");
    msg(@nginx);
    write_file($nginx_fh, @nginx);

    run("sudo cp $nginx_filename /etc/nginx/sites-available/$apex.conf");
    run("sudo chmod 644 /etc/nginx/sites-available/$apex.conf");

    # only do the symlink if it doesn't already exist
    if ( ! -l "/etc/nginx/sites-enabled/$apex.conf" ) {
        run("sudo ln -s /etc/nginx/sites-available/$apex.conf /etc/nginx/sites-enabled/$apex.conf");
    }

    # restart Nginx
    run("sudo service nginx restart");
}
elsif ( $is_nginx_tailscale ) {
    msg("Nginx with Tailscale Auth.");

    # From : https://tailscale.com/blog/tailscale-auth-nginx/

    my @nginx;
    push(@nginx, "server {\n");
    push(@nginx, "    listen        80;\n");
    push(@nginx, "    server_name   $apex;\n");
    push(@nginx, "    location      /auth/tailscale {\n");
    push(@nginx, "        internal;\n");
    push(@nginx, "        proxy_pass http://unix:/run/tailscale.nginx-auth.sock;\n");
    push(@nginx, "        proxy_pass_request_body off;\n");
    push(@nginx, "        proxy_set_header Host \$http_host;\n");
    push(@nginx, "        proxy_set_header Remote-Addr \$remote_addr;\n");
    push(@nginx, "        proxy_set_header Remote-Port \$remote_port;\n");
    push(@nginx, "        proxy_set_header Original-URI \$request_uri;\n");
    push(@nginx, "    }\n");
    push(@nginx, "    location / {\n");
    push(@nginx, "        auth_request       /auth/tailscale;\n");
    push(@nginx, "        auth_request_set   \$auth_user \$upstream_http_tailscale_user;\n");
    push(@nginx, "        auth_request_set   \$auth_name \$upstream_http_tailscale_name;\n");
    push(@nginx, "        auth_request_set   \$auth_login \$upstream_http_tailscale_login;\n");
    push(@nginx, "        auth_request_set   \$auth_tailnet \$upstream_http_tailscale_tailnet;\n");
    push(@nginx, "        auth_request_set   \$auth_profile_picture \$upstream_http_tailscale_profile_picture;\n");
    push(@nginx, "        proxy_set_header   X-Webauth-User \"\$auth_user\";\n");
    push(@nginx, "        proxy_set_header   X-Webauth-Name \"\$auth_name\";\n");
    push(@nginx, "        proxy_set_header   X-Webauth-Login \"\$auth_login\";\n");
    push(@nginx, "        proxy_set_header   X-Webauth-Tailnet \"\$auth_tailnet\";\n");
    push(@nginx, "        proxy_set_header   X-Webauth-Profile-Picture \"\$auth_profile_picture\";\n");
    push(@nginx, "        proxy_set_header   X-Real-IP           \$remote_addr;\n");
    push(@nginx, "        proxy_set_header   X-Forwarded-For     \$proxy_add_x_forwarded_for;\n");
    push(@nginx, "        proxy_set_header   Host                \$http_host;\n");
    push(@nginx, "        proxy_pass         http://localhost:$port;\n");
    push(@nginx, "    }\n");
    push(@nginx, "    access_log    /var/log/nginx/$apex.access.log;\n");
    push(@nginx, "    error_log     /var/log/nginx/$apex.error.log;\n");
    push(@nginx, "}\n");
    push(@nginx, "\n");

    if ( $www ) {
        # just like CertBot, a simple redirect will suffice.
        push(@nginx, "server {\n");
        push(@nginx, "    listen        80;\n");
        push(@nginx, "    server_name   www.$apex;\n");
        push(@nginx, "    access_log    /var/log/nginx/$apex.access.log;\n");
        push(@nginx, "    error_log     /var/log/nginx/$apex.error.log;\n");
        push(@nginx, "    return        301 \$scheme://$apex\$request_uri;\n");
        push(@nginx, "}\n");
    }

    # write this out to a file
    my $nginx_fh = File::Temp->new();
    my $nginx_filename = $nginx_fh->filename;

    msg("Writing $nginx_filename");
    msg(@nginx);
    write_file($nginx_fh, @nginx);

    run("sudo cp $nginx_filename /etc/nginx/sites-available/$apex.conf");

    # only do the symlink if it doesn't already exist
    if ( ! -l "/etc/nginx/sites-enabled/$apex.conf" ) {
        run("sudo ln -s /etc/nginx/sites-available/$apex.conf /etc/nginx/sites-enabled/$apex.conf");
    }

    # restart Nginx
    run("sudo service nginx restart");
}
else {
    msg("No Nginx configuration is being created or written.");
}

## --------------------------------------------------------------------------------------------------------------------
# CertBot

sep();
title("CertBot");

if ( $is_nginx_certbot ) {
    if ( $is_nginx_done ) {
        msg("Since nginx was set up previously, you don't need to run");
        msg("certbot again if you have already set up a certificate.");
        msg("");
        msg("If this message is incorrect, you may run it with:");
    }
    else {
        msg("To tell CertBot about this new Nginx config, you can run:");
    }
    msg("");
    msg("\$ sudo certbot --nginx");
}
else {
    msg("CertBot has not been requested for this install.");
}

## --------------------------------------------------------------------------------------------------------------------

sep();
title("Complete!");

## --------------------------------------------------------------------------------------------------------------------

sub title {
    my ($msg) = @_;
    print "-----> $msg\n";
}

sub msg {
    my (@msg) = @_;
    chomp @msg;
    for my $line ( @msg ) {
        print "       $line\n";
    }
}

sub err {
    my (@msg) = @_;
    chomp @msg;
    for my $line ( @msg ) {
        print "Error: $line\n";
    }
}

sub sep {
    print "\n";
}

sub run {
    my ($cmd) = @_;

    my @stdin;
    my @stdout;
    my @stderr;

    msg("\$ $cmd");
    run3($cmd, \undef, \@stdout, \@stderr);
    if ( $? ) {
        err(@stderr);
        exit $?;
    }
    msg(@stdout);
}

## --------------------------------------------------------------------------------------------------------------------
