#!/usr/bin/env perl
## --------------------------------------------------------------------------------------------------------------------

use Modern::Perl;
use File::Slurp;
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

## --------------------------------------------------------------------------------------------------------------------
# There are a number of things we want to do when we deploy:

title("The Deployer is Deploying - Stand Back!");

msg("User        : $ENV{USER}");
msg("Current Dir : $dir");
msg("Name        : $name");
msg("Safe Name   : $safe_name");

## --------------------------------------------------------------------------------------------------------------------
# Code

sep();
title("Updating the Code");
run('git fetch --verbose');
run('git rebase origin/master');

## --------------------------------------------------------------------------------------------------------------------
# Dirs

sep();
title("Creating Dirs");

my @dirs = read_file('deployer/dirs');
chomp @dirs;
for my $line ( @dirs ) {
    # msg("Creating dir $line");
    run("sudo mkdir -p $line");
    # msg("Setting ownership to the current user");
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
