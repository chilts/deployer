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
# Setup

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
my $is_nginx_done = 0;

## --------------------------------------------------------------------------------------------------------------------
# There are a number of things we want to do when we deploy:

title("The Deployer is Deploying - Stand Back!");

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
        run("dpkg-query --show $pkg");
    }
}
else {
    msg("No 'packages' file.");
}

## --------------------------------------------------------------------------------------------------------------------
# Code

sep();
title("Updating the Code");
run('git fetch --verbose');
run('git rebase origin/master');

## --------------------------------------------------------------------------------------------------------------------
# Update Packages

if ( $is_node ) {
    sep();
    title("Installing NPM Packages");
    run('npm install');
}
if ( $is_golang ) {
    sep();
    title("Building GoLang");
    run('gb build');
}
if ( $is_nebulous ) {
    sep();
    title("Installing NPM Packages");
    run('npm install');
}

## --------------------------------------------------------------------------------------------------------------------
# Make

sep();
title("Making the Project");
if ( -f "Makefile" ) {
    run("make");
}
else {
    msg("No 'Makefile'.");
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
            run("curl -X POST -s --form 'input=\@filename.jpg;type=image/jpg' https://jpgoptimiser.com/optimise > $filename.min.jpgg");
        }
    }
}
else {
    msg("No 'minify' file.");
}

## --------------------------------------------------------------------------------------------------------------------
# Dirs

sep();
title("Creating Dirs");

# for supervisord logging
run("sudo mkdir -p /var/log/$name/");

my @dirs = read_file('deployer/dirs');
chomp @dirs;
for my $line ( @dirs ) {
    run("sudo mkdir -p $line");
    run("sudo chown $username.$username $line");
}

## --------------------------------------------------------------------------------------------------------------------
# Cron

sep();
title("Cron");

if ( -f "deployer/cron.d" ) {
    run("sudo cp deployer/cron.d /etc/cron.d/$safe_name");
}
else {
    msg("No cron found");
}

## --------------------------------------------------------------------------------------------------------------------
# Supervisor

sep();
title("Supervisor");

# create each line of the supervisor file
my @supervisor;

# create each line
push(@supervisor, "[program:$safe_name]\n");
push(@supervisor, "directory = $dir\n");
if ( $is_node ) {
    push(@supervisor, "command = node server.js\n");
}
elsif ( $cmd ) {
    push(@supervisor, "command = $cmd\n");
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

run("sudo service supervisor restart");

## --------------------------------------------------------------------------------------------------------------------
# Nginx

sep();
title("Nginx");

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

    run("sudo service nginx restart");
}
else {
    $is_nginx_done = 1;
    msg("Nginx config already set up. You'll need to make changes manually to force any changes.");
}

## --------------------------------------------------------------------------------------------------------------------
# CertBot

sep();
title("CertBot");

if ( $is_nginx_done ) {
    msg("Since nginx was set up previously, you don't need to run");
    msg("certbot now if you have already set up a certificate.");
    msg("");
    msg("If this message is incorrect, you may run it with:");
}
else {
    msg("To tell CertBot about this new Nginx config, you can run:");
}
msg("");
msg("\$ sudo certbot --nginx");

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
