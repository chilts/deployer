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
# Always update the code first since `deployer/env` needs to be read after an update.

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

print "name = $name\n";
print "safe_name = $safe_name\n";

my $is_nginx_certbot = 1;
my $is_nginx_origin_cert = 0;
my $is_nginx_done = 0;

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

# overwrite these since we need to set them, not from the env.
$env->{NAME} = $name;
$env->{SAFE_NAME} = $safe_name;

# check we have some env vars
my @requireds = (
    'NAME',
    'APEX',
    'PORT',
    'WWW',
    'CMD',
);

# if pg-dump is enabled, require these additional env vars
if ( -f "deployer/pg-dump" ) {
    push(@requireds, 'DATABASE_URL');
    push(@requireds, 'DEPLOYER_BACKUP_DIR');
}

for my $required ( @requireds ) {
    unless ( exists $env->{$required} && length($env->{$required}) ) {
        print STDERR "Env var '$required' is required\n";
        exit 2;
    }
}

# $name (and $safe_name) comes from the current dir (not an env var) and a derivative
my $apex = $env->{APEX};
my $port = $env->{PORT};
my $www = defined $env->{WWW} ? ($env->{WWW}+0) : 1; # default: add the `www.$apex` server
my $cmd = $env->{CMD};

## --------------------------------------------------------------------------------------------------------------------
# Packages

sep();
title("Checking Packages");

if ( -f 'deployer/packages' ) {
    my @pkgs = read_file('deployer/packages');
    chomp @pkgs;
    for my $pkg ( @pkgs ) {
        run("dpkg-query --show $pkg");
    }
}
else {
    msg("No 'packages' file.");
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
    my @dirs = read_file_and_sub_env('deployer/dirs');
    chomp @dirs;
    for my $line ( @dirs ) {
        run("sudo mkdir -p '$line'");
        run("sudo chown $username.$username '$line'");
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
    my @cron = read_file_and_sub_env('deployer/cron.d');

    my $cron_fh = File::Temp->new();
    my $cron_filename = $cron_fh->filename;

    msg("Writing $cron_filename");
    msg(@cron);
    write_file($cron_fh, @cron);

    run("sudo cp $cron_filename '/etc/cron.d/$safe_name'");
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
    run("sudo mkdir -p '/var/log/$name/'");

    # create each line of the supervisor file
    my @supervisor;

    # create each line
    push(@supervisor, "[program:$safe_name]\n");
    push(@supervisor, "directory = $dir\n");
    push(@supervisor, "command = $cmd\n");
    push(@supervisor, "user = $username\n");
    push(@supervisor, "autostart = true\n");
    push(@supervisor, "autorestart = true\n");
    push(@supervisor, "start_retries = 3\n");
    push(@supervisor, "stdout_logfile = /var/log/supervisor/$name/stdout.log\n");
    push(@supervisor, "stdout_logfile_maxbytes = 50MB\n");
    push(@supervisor, "stdout_logfile_backups = 20\n");
    push(@supervisor, "stderr_logfile = /var/log/supervisor/$name/stderr.log\n");
    push(@supervisor, "stderr_logfile_maxbytes = 50MB\n");
    push(@supervisor, "stderr_logfile_backups = 20\n");

    # environment
    push(@supervisor, "environment = NODE_ENV=\"production\"");
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

if ( -f "deployer/key.age" && -f "deployer/apex.key.age" && -f "deployer/apex.pem" ) {
    msg("It looks like you have all files of an Origin Certificate from Cloudflare.");
    msg("");
    msg("Copying 'apex.pem' to '/etc/ssl/$apex.pem'");
    run("sudo cp deployer/apex.pem '/etc/ssl/$apex.pem'");
    msg("");
    msg("Decrypting 'apex.key.age' to 'apex.key");
    run("age --decrypt --identity=deployer/key.age --output=deployer/apex.key deployer/apex.key.age");
    msg("");
    msg("Copying 'apex.key' to '/etc/ssl/private/$apex.key");
    run("sudo cp deployer/apex.key '/etc/ssl/private/$apex.key'");
    msg("");
    msg("Fixing ownership and permissions on '/etc/ssl/private/$apex.key");
    run("sudo chown root.ssl-cert '/etc/ssl/private/$apex.key'");
    run("sudo chmod 640 '/etc/ssl/private/$apex.key'");
    msg("");
    msg("Removing 'apex.key'");
    run("rm deployer/apex.key");

    $is_nginx_certbot = 0;
    $is_nginx_origin_cert = 1;
}
else {
    msg("An Origin Certificate has not been requested for this install.");
}

## --------------------------------------------------------------------------------------------------------------------
# Nginx

sep();
title("Nginx");

# Firstly we need to figure out if we are doing an Origin Cert (from Cloudflare)
# using CertBot (the default).

my $nginx_conf_available = "/etc/nginx/sites-available/$apex.conf";
my $nginx_conf_enabled = "/etc/nginx/sites-enabled/$apex.conf";

if ( $is_nginx_certbot ) {
    # Skip if the Nginx config already exists.
    if ( ! -f $nginx_conf_available ) {
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
        push(@nginx, "    client_max_body_size 25M;\n");
        push(@nginx, "    access_log /var/log/nginx/$apex.access.log;\n");
        push(@nginx, "    error_log /var/log/nginx/$apex.error.log;\n");
        push(@nginx, "}\n");
        push(@nginx, "\n");

        if ( $www ) {
            push(@nginx, "server {\n");
            push(@nginx, "    listen      80;\n");
            push(@nginx, "    server_name www.$apex;\n");
            push(@nginx, "    access_log /var/log/nginx/www.$apex.access.log;\n");
            push(@nginx, "    error_log /var/log/nginx/www.$apex.error.log;\n");
            push(@nginx, "    return      301 \$scheme://$apex\$request_uri;\n");
            push(@nginx, "}\n");
        }

        # write this out to a file
        my $nginx_fh = File::Temp->new();
        my $nginx_filename = $nginx_fh->filename;

        msg("Writing $nginx_filename");
        msg(@nginx);
        write_file($nginx_fh, @nginx);

        run("sudo cp $nginx_filename '$nginx_conf_available'");

        # only do the symlink if it doesn't already exist
        if ( ! -l $nginx_conf_enabled ) {
            run("sudo ln -s '$nginx_conf_available' '$nginx_conf_enabled'");
        }

        run("sudo service nginx restart");
    }
    else {
        $is_nginx_done = 1;
        msg("Nginx config already set up. You'll need to make changes manually to force any changes.");
    }
}
elsif ( $is_nginx_origin_cert ) {
    msg("Origin Certificate from Cloudflare");

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
        push(@nginx, "    access_log          /var/log/nginx/www.$apex.access.log;\n");
        push(@nginx, "    error_log           /var/log/nginx/www.$apex.error.log;\n");
        push(@nginx, "    return 301          https://$apex\$request_uri;\n");
        push(@nginx, "}\n");
        push(@nginx, "\n");

        push(@nginx, "server {\n");
        push(@nginx, "    listen              80;\n");
        push(@nginx, "    server_name         www.$apex;\n");
        push(@nginx, "    access_log          /var/log/nginx/www.$apex.access.log;\n");
        push(@nginx, "    error_log           /var/log/nginx/www.$apex.error.log;\n");
        push(@nginx, "    return              301 https://$apex\$request_uri;\n");
        push(@nginx, "}\n");
    }

    # write this out to a file
    my $nginx_fh = File::Temp->new();
    my $nginx_filename = $nginx_fh->filename;

    msg("Writing $nginx_filename");
    msg(@nginx);
    write_file($nginx_fh, @nginx);

    run("sudo cp $nginx_filename '$nginx_conf_available'");
    run("sudo chmod 644 '$nginx_conf_available'");

    # only do the symlink if it doesn't already exist
    if ( ! -l $nginx_conf_enabled ) {
        run("sudo ln -s '$nginx_conf_available' '$nginx_conf_enabled'");
    }

    run("sudo service nginx restart");
}
else {
    msg("No Nginx configuration is being created or written.");
}

## --------------------------------------------------------------------------------------------------------------------
# CertBot

sep();
title("CertBot");

if ( -f "deployer/certbot" ) {
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
# Pg Dump

sep();
title("Pg Dump");

if ( -f "deployer/pg-dump" ) {
    my $backup_dir = $env->{DEPLOYER_BACKUP_DIR};
    my $database_url = $env->{DATABASE_URL};
    my $dump_dir = "$backup_dir/database/$name";

    # Ensure dump directory exists
    run("sudo mkdir -p '$dump_dir'");
    run("sudo chown $username.$username '$dump_dir'");

    my @cron;
    push(@cron, "#  hr  mn  dom mon dow\n");
    push(@cron, "    0   1    *   *   *   $username   /home/$username/bin/deployer-pg-dump.sh $dump_dir $database_url\n");

    my $cron_fh = File::Temp->new();
    my $cron_filename = $cron_fh->filename;

    msg("Writing $cron_filename");
    msg(@cron);
    write_file($cron_fh, @cron);

    run("sudo cp $cron_filename '/etc/cron.d/deployer-pg-dump--$safe_name'");
}
else {
    msg("No pg-dump file found");

    # remove the cron file if it exists (feature was previously enabled but now disabled)
    if ( -f "/etc/cron.d/deployer-pg-dump--$safe_name" ) {
        msg("Removing old pg-dump cron file");
        run("sudo rm '/etc/cron.d/deployer-pg-dump--$safe_name'");
    }
}

## --------------------------------------------------------------------------------------------------------------------

sep();
title("Complete!");

## --------------------------------------------------------------------------------------------------------------------

sub read_file_and_sub_env {
    my ($filename) = @_;

    my @lines = read_file($filename);

    print "---\n";
    print @lines, "\n";
    print "---\n";

    foreach my $line (@lines) {
        foreach my $key (keys %{$env}) {
            $line =~ s/\$$key/$env->{$key}/g;
        }
    }

    print "---\n";
    print @lines, "\n";
    print "---\n";

    return @lines;
}

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
