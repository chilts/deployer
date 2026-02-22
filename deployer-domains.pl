#!/usr/bin/env perl
## --------------------------------------------------------------------------------------------------------------------

use Modern::Perl;
use File::Slurp;
use File::Temp ();
use IPC::Run3;
use Cwd qw();
use File::Basename qw();
use Getopt::Long;

## --------------------------------------------------------------------------------------------------------------------

my $remove = 0;
GetOptions("remove" => \$remove) or die "Usage: $0 [--remove] [domain ...]\n";

my @args = @ARGV;

## --------------------------------------------------------------------------------------------------------------------

title("Deployer Domains - Custom Domain Mapping");

# check we can get sudo
run("sudo echo");

## --------------------------------------------------------------------------------------------------------------------
# Verify directory structure

sep();
title("Checking Setup");

unless ( -d "deployer" ) {
    err("No 'deployer/' directory found. Are you in a webapp directory?");
    exit 2;
}

unless ( -d "deployer/domains" ) {
    err("No 'deployer/domains/' directory found.");
    err("Run deployer-domain-setup.sh <domain> to add your first custom domain.");
    exit 2;
}

unless ( -f "deployer/domains/key.age" ) {
    err("No 'deployer/domains/key.age' found.");
    err("Run deployer-domain-setup.sh <domain> to set up the age identity.");
    exit 2;
}

## --------------------------------------------------------------------------------------------------------------------
# Read PORT from deployer/env

sep();
title("Reading Configuration");

unless ( -f "deployer/env" ) {
    err("No 'deployer/env' file found. Run deployer.pl first.");
    exit 2;
}

my $env = read_key_value_file('deployer/env');

# Resolve ? values from ENV_ files (must already be configured)
while (my ($k, $v) = each(%$env)) {
    if ($v eq "?") {
        my $filename = "deployer/ENV_$k";
        if ( -f $filename ) {
            my $value = read_file($filename);
            chomp $value;
            $env->{$k} = $value;
        }
        else {
            err("$k is not yet configured. Run deployer.pl first.");
            exit 2;
        }
    }
}

my $port = $env->{PORT};
unless ( defined $port && length($port) ) {
    err("PORT is not configured in deployer/env. Run deployer.pl first.");
    exit 2;
}

# Validate PORT
if ( $port !~ /^\d+$/ || $port < 1 || $port > 65535 ) {
    err("PORT must be a numeric value between 1 and 65535, got '$port'");
    exit 2;
}

my $apex = $env->{APEX} // '';

# Set default for NGINX_CLIENT_MAX_BODY_SIZE
my $client_max_body_size = $env->{NGINX_CLIENT_MAX_BODY_SIZE} // '25M';

msg("PORT                    : $port");
msg("APEX                    : $apex");
msg("NGINX_CLIENT_MAX_BODY_SIZE : $client_max_body_size");

## --------------------------------------------------------------------------------------------------------------------
# Determine domains to process

sep();
title("Determining Domains");

my @domains;

if ( @args ) {
    # Specific domains from command line
    for my $domain ( @args ) {
        # Validate domain name
        if ( $domain !~ /^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$/ || $domain =~ /\.\./ ) {
            err("Domain '$domain' contains invalid characters. Only alphanumeric, hyphens, and dots allowed.");
            exit 2;
        }

        if ( !$remove ) {
            # For process mode, verify the domain directory exists
            unless ( -d "deployer/domains/$domain" ) {
                err("No directory 'deployer/domains/$domain/' found.");
                err("Run deployer-domain-setup.sh $domain to add this domain.");
                exit 2;
            }
        }

        push(@domains, $domain);
    }
}
else {
    if ( $remove ) {
        err("--remove requires a domain name argument.");
        exit 2;
    }

    # All domains: scan deployer/domains/ for subdirectories
    opendir(my $dh, "deployer/domains") or die "Cannot open deployer/domains/: $!";
    while (my $entry = readdir($dh)) {
        next if $entry eq '.' || $entry eq '..';
        next unless -d "deployer/domains/$entry";
        push(@domains, $entry);
    }
    closedir($dh);

    @domains = sort @domains;
}

if ( !@domains ) {
    err("No custom domains found in deployer/domains/.");
    err("Run deployer-domain-setup.sh <domain> to add a custom domain.");
    exit 2;
}

msg("Domains: " . join(", ", @domains));

## --------------------------------------------------------------------------------------------------------------------
# Handle removal

if ( $remove ) {
    sep();
    title("Removing Domains");

    for my $domain ( @domains ) {
        sep();
        title("Removing $domain");

        # Check it's not the APEX domain
        if ( $apex && $domain eq $apex ) {
            err("'$domain' is the APEX domain. Use deployer.pl to manage it.");
            exit 2;
        }

        my $nginx_conf_available = "/etc/nginx/sites-available/$domain.conf";
        my $nginx_conf_enabled = "/etc/nginx/sites-enabled/$domain.conf";

        if ( -l $nginx_conf_enabled ) {
            msg("Removing symlink $nginx_conf_enabled");
            run("sudo rm '$nginx_conf_enabled'");
        }
        else {
            msg("No symlink at $nginx_conf_enabled");
        }

        if ( -f $nginx_conf_available ) {
            msg("Removing $nginx_conf_available");
            run("sudo rm '$nginx_conf_available'");
        }
        else {
            msg("No config at $nginx_conf_available");
        }

        if ( -f "/etc/ssl/$domain.pem" ) {
            msg("Removing /etc/ssl/$domain.pem");
            run("sudo rm '/etc/ssl/$domain.pem'");
        }

        if ( -f "/etc/ssl/private/$domain.key" ) {
            msg("Removing /etc/ssl/private/$domain.key");
            run("sudo rm '/etc/ssl/private/$domain.key'");
        }

        msg("");
        msg("Domain $domain removed from nginx and SSL.");
        msg("");
        msg("To also remove the cert files from the repo:");
        msg("  rm -rf deployer/domains/$domain");
        msg("  git add deployer/domains/$domain");
        msg("  git commit -m 'Remove custom domain $domain'");
    }

    sep();
    title("Restarting Nginx");
    run("sudo nginx -t");
    run("sudo service nginx restart");

    sep();
    title("Complete!");
    exit 0;
}

## --------------------------------------------------------------------------------------------------------------------
# Process domains: decrypt identity once

sep();
title("Decrypting Age Identity");

my $identity_fh = File::Temp->new(UNLINK => 1);
my $identity_file = $identity_fh->filename;
chmod 0600, $identity_file;

msg("Decrypting deployer/domains/key.age (passphrase required)...");
run("age --decrypt --output='$identity_file' deployer/domains/key.age");

## --------------------------------------------------------------------------------------------------------------------
# Process each domain

for my $domain ( @domains ) {
    sep();
    title("Processing $domain");

    # Check it's not the APEX domain
    if ( $apex && $domain eq $apex ) {
        err("'$domain' is the APEX domain. Use deployer.pl to manage it. Skipping.");
        next;
    }

    # Validate domain name
    if ( $domain !~ /^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$/ || $domain =~ /\.\./ ) {
        err("Domain '$domain' contains invalid characters. Skipping.");
        next;
    }

    # Verify cert files exist
    unless ( -f "deployer/domains/$domain/cert.pem" ) {
        err("Missing deployer/domains/$domain/cert.pem. Skipping.");
        next;
    }

    unless ( -f "deployer/domains/$domain/cert.key.age" ) {
        err("Missing deployer/domains/$domain/cert.key.age. Skipping.");
        next;
    }

    # Install public certificate
    msg("");
    msg("Copying cert.pem to /etc/ssl/$domain.pem");
    run("sudo cp 'deployer/domains/$domain/cert.pem' '/etc/ssl/$domain.pem'");

    # Decrypt and install private key
    msg("");
    msg("Decrypting cert.key.age...");
    my $temp_key_fh = File::Temp->new(UNLINK => 1);
    my $temp_key_file = $temp_key_fh->filename;
    chmod 0600, $temp_key_file;

    run("age --decrypt --identity='$identity_file' --output='$temp_key_file' 'deployer/domains/$domain/cert.key.age'");

    msg("Copying decrypted key to /etc/ssl/private/$domain.key");
    run("sudo cp '$temp_key_file' '/etc/ssl/private/$domain.key'");

    msg("Fixing ownership and permissions on /etc/ssl/private/$domain.key");
    run("sudo chown root.ssl-cert '/etc/ssl/private/$domain.key'");
    run("sudo chmod 640 '/etc/ssl/private/$domain.key'");

    # Generate nginx config
    msg("");
    msg("Generating nginx config for $domain");

    my @nginx = generate_domain_nginx($domain, $port, $client_max_body_size);

    my $nginx_fh = File::Temp->new();
    my $nginx_filename = $nginx_fh->filename;

    msg("Writing $nginx_filename");
    msg(@nginx);
    write_file($nginx_fh, @nginx);

    my $nginx_conf_available = "/etc/nginx/sites-available/$domain.conf";
    my $nginx_conf_enabled = "/etc/nginx/sites-enabled/$domain.conf";

    run("sudo cp '$nginx_filename' '$nginx_conf_available'");
    run("sudo chmod 644 '$nginx_conf_available'");

    # only do the symlink if it doesn't already exist
    if ( ! -l $nginx_conf_enabled ) {
        run("sudo ln -s '$nginx_conf_available' '$nginx_conf_enabled'");
    }

    msg("");
    msg("Domain $domain configured.");
}

## --------------------------------------------------------------------------------------------------------------------
# Validate and restart nginx

sep();
title("Validating Nginx Configuration");

my @stdout;
my @stderr;
msg("\$ sudo nginx -t");
run3("sudo nginx -t", \undef, \@stdout, \@stderr);
if ( $? ) {
    err(@stderr);
    err("Nginx configuration test failed. Nginx was NOT restarted.");
    err("Fix the configuration and re-run.");
    exit 1;
}
msg(@stdout);
msg(@stderr); # nginx -t outputs to stderr even on success
msg("Nginx configuration test passed.");

sep();
title("Restarting Nginx");
run("sudo service nginx restart");

## --------------------------------------------------------------------------------------------------------------------

sep();
title("Complete!");

## --------------------------------------------------------------------------------------------------------------------

sub generate_domain_nginx {
    my ($domain, $port, $client_max_body_size) = @_;
    my @nginx;

    # HTTPS server
    push(@nginx, "# Managed by deployer-domains.pl - do not edit manually\n");
    push(@nginx, "server {\n");
    push(@nginx, "    listen              443;\n");
    push(@nginx, "    server_name         $domain;\n");
    push(@nginx, "    ssl                 on;\n");
    push(@nginx, "    ssl_certificate     /etc/ssl/$domain.pem;\n");
    push(@nginx, "    ssl_certificate_key /etc/ssl/private/$domain.key;\n");
    push(@nginx, "    location / {\n");
    push(@nginx, "        proxy_set_header X-Real-IP \$remote_addr;\n");
    push(@nginx, "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n");
    push(@nginx, "        proxy_set_header Host \$http_host;\n");
    push(@nginx, "        proxy_pass http://localhost:$port;\n");
    push(@nginx, "    }\n");
    push(@nginx, "    client_max_body_size $client_max_body_size;\n");
    push(@nginx, "    access_log          /var/log/nginx/$domain.access.log;\n");
    push(@nginx, "    error_log           /var/log/nginx/$domain.error.log;\n");
    push(@nginx, "}\n");
    push(@nginx, "\n");

    # HTTP redirect to HTTPS
    push(@nginx, "server {\n");
    push(@nginx, "    listen              80;\n");
    push(@nginx, "    server_name         $domain;\n");
    push(@nginx, "    return              301 https://$domain\$request_uri;\n");
    push(@nginx, "}\n");

    return @nginx;
}

sub read_key_value_file {
    my ($filename) = @_;
    my $hash = {};
    my @lines = read_file($filename);
    for my $line (@lines) {
        chomp $line;
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;
        if ($line =~ /^\s*([^:]+?)\s*:\s*(.*?)\s*$/) {
            $hash->{$1} = $2;
        }
    }
    return $hash;
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
