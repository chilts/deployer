#!/usr/bin/env perl
## --------------------------------------------------------------------------------------------------------------------

use Modern::Perl;
use Config::Simple;
use File::Slurp;
use File::Temp ();
use IPC::Run3;
use Cwd qw();
use File::Basename qw();

## --------------------------------------------------------------------------------------------------------------------
# Setup

# You wouldn't do this normally since it depends on an ENV var, instead use User or File::HomeDir,
my $username = $ENV{USER};

my $dir = Cwd::cwd();
my ($name) = File::Basename::fileparse($dir);
my $safe_name = $name;
$safe_name =~ s/\./-/g;

my $is_node = 0;
if ( -f 'package.json' || -f 'package-lock.json' ) {
    $is_node = 1;
}

## --------------------------------------------------------------------------------------------------------------------
# There are a number of things we want to do when we deploy:

title("The Deployer is Deploying - Stand Back!");

my $env = {};
if ( -f 'deployer/env' ) {
    my $cfg = new Config::Simple('deployer/env');
    if ( defined $cfg ) {
        %$env = $cfg->vars();
    }
}

msg("User        : $ENV{USER}");
msg("Current Dir : $dir");
msg("Name        : $name");
msg("Safe Name   : $safe_name");
msg("Is Node.js? : $is_node");
msg("Env         :");
while (my ($k, $v) = each(%$env)) {
    msg(" - $k=$v")
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
    title("Installing Packages");
    run('npm install');
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
    push(@supervisor, "command = npm start\n");
}
else {
    push(@supervisor, "command = echo 'Error: Unknown deployer command.'\n");
}
push(@supervisor, "user = $username\n");
push(@supervisor, "autostart = true\n");
push(@supervisor, "autorestart = true\n");
push(@supervisor, "stdout_logfile = /var/log/$name/stdout.log\n");
push(@supervisor, "stdout_logfile_maxbytes=50MB\n");
push(@supervisor, "stdout_logfile_backups=20\n");
push(@supervisor, "stderr_logfile = /var/log/$name/stderr.log\n");
push(@supervisor, "stderr_logfile_maxbytes=50MB\n");
push(@supervisor, "stderr_logfile_backups=20\n");
if ( $is_node ) {
    push(@supervisor, "environment = NODE_ENV=production\n");
}

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

# ToDo: check if this is a naked domain or a sub-domain

# assume naked domain for now
my $domain = $name;
my @nginx;
push(@nginx, "server {\n");
push(@nginx, "    listen      80;\n");
push(@nginx, "    server_name $domain;\n");
push(@nginx, "    location    / {\n");
push(@nginx, "        proxy_set_header   X-Real-IP \$remote_addr;\n");
push(@nginx, "        proxy_set_header   Host      \$http_host;\n");
push(@nginx, "        proxy_pass         http://localhost:$env->{port};\n");
push(@nginx, "    }\n");
push(@nginx, "}\n");
push(@nginx, "\n");
push(@nginx, "server {\n");
push(@nginx, "    listen      80;\n");
push(@nginx, "    server_name www.$domain;\n");
push(@nginx, "    return      301 \$scheme://$domain\$request_uri;\n");
push(@nginx, "}\n");

# write this out to a file
my $nginx_fh = File::Temp->new();
my $nginx_filename = $nginx_fh->filename;

msg("Writing $nginx_filename");
msg(@nginx);
write_file($nginx_fh, @nginx);

run("sudo cp $nginx_filename /etc/nginx/sites-available/$domain.conf");

# only do the symlink if it doesn't already exist
if ( ! -l "/etc/nginx/sites-enabled/$domain.conf" ) {
    run("sudo ln -s /etc/nginx/sites-available/$domain.conf /etc/nginx/sites-enabled/$domain.conf");
}

run("sudo service nginx restart");

## --------------------------------------------------------------------------------------------------------------------
# CertBot

sep();
title("CertBot");

msg("");
msg("Now run : sudo certbot --nginx");
msg("");

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
