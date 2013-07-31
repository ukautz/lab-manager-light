package LML::VMcreate::VMproperties;

use strict;
use warnings;
use Carp;
use LWP::Simple qw(get);
use CGI ':standard';
use Data::Dumper;
use Getopt::Long;
use JSON;
use LML::VMnetworks;
use LML::VMresources;
use LML::VMplacement;

sub new {
    my ( $class, $config, $lab, $test_args ) = @_;

    croak( "1st argument must be an instance of LML::Config called at " . ( caller 0 )[3] ) unless ( ref($config) eq "LML::Config" );
    croak( "2nd argument must be an instance of LML::Lab called at " .    ( caller 0 )[3] ) unless ( ref($lab)    eq "LML::Lab" );

    my $vm_name;
    my $username;
    my $expiration_date;
    my $esx_host;
    my $vm_folder;
    my $force_boot_target;
    my $force_network = undef;

    # are we called via webui?
    if ( exists $ENV{GATEWAY_INTERFACE} ) {
        $vm_name           = param('name');
        $username          = param('username');
        $expiration_date   = param('expiration');
        $esx_host          = param('esx_host');
        $vm_folder         = param('folder');
        $force_boot_target = param('force_boot_target') || "default";
        $force_network     = param('force_network');
        # or are we called via commandline
    }
    elsif ( @ARGV > 0 ) {
        # get the long commandline options
        GetOptions(
                    "name=s"              => \$vm_name,
                    "username=s"          => \$username,
                    "expiration=s"        => \$expiration_date,
                    "esx_host=s"          => \$esx_host,
                    "folder=s"            => \$vm_folder,
                    "force_boot_target=s" => \$force_boot_target,
                    "force_network=s"     => \$force_network,
        );

    }
    elsif ( defined($test_args) && ref($test_args) eq "HASH" ) {
        # for testing purpose

        $vm_name           = $test_args->{name};
        $username          = $test_args->{username};
        $expiration_date   = $test_args->{expiration};
        $esx_host          = $test_args->{esx_host};
        $vm_folder         = $test_args->{folder};
        $force_boot_target = $test_args->{force_boot_target} || "default";
        $force_network     = $test_args->{force_network};
    }
    # We have nothing, print help
    else {
        LML::VMcreate::VMproperties->_error("no Parameters");
    }

    my %parameters_for_validation = (
        vm_name         => $vm_name,
        username        => $username,
        expiration_date => $expiration_date,
        #                                   esx_host          => $esx_host,
        #                                   force_boot_target => $force_boot_target,
        #                                   vm_folder         => $vm_folder
    );

    if ( defined($test_args) && ref($test_args) eq "HASH" ) {
        # TODO: remove this hack
        $parameters_for_validation{is_test_mode} = 1;
    }

    # paramters must be set and valid!
    my $check_param = LML::VMcreate::VMproperties->_check_parameter( $config, %parameters_for_validation );

    # was the paramter check unsuccessful?
    if ($check_param) {
        LML::VMcreate::VMproperties->_error($check_param);
    }

    my $self = {
        config            => $config,
        lab               => $lab,
        linebreak         => '\n',                 # TODO: do we need this?
        guestid           => 'rhel6_64Guest',
        custom_fields     => {},
        vm_name           => $vm_name,
        username          => $username,
        expiration_date   => $expiration_date,
        esx_host          => $esx_host,
        vm_folder         => $vm_folder,
        force_boot_target => $force_boot_target,
        force_network     => $force_network,

    };

    # print STDERR "DEBUG - VMproperties: " . Data::Dumper->Dump( [ %{$self} ] ) . "\n";

    bless( $self, $class );
    return $self;
}

# generate an array of hashes, where each hash
# represents a virtual machine to be created
# ============================================
sub generate_vms_array {
    my ($self) = @_;

    # assemble custom fields hash
    my %custom_fields = (
                          'Contact User ID'   => $self->{username},
                          'Expires'           => $self->{expiration_date},
                          'Force Boot'        => 'ON',
                          'Force Boot Target' => $self->{force_boot_target},
    );

    # because it is possible that a machine don't exist in subversion we call
    # the generation now (temporary disabled)
    get sprintf $self->{config}->get( "vm_spec", "host_announcement" ), $self->{vm_name};

    # get now the json spec for this vm
    my $answer = LWP::Simple::get sprintf $self->{config}->get( "vm_spec", "host_spec" ), $self->{vm_name};
    # check if we got something from web call
    $self->_error( "Unable to get JSON description file for VM " . $self->{vm_name} . " from " . $self->{config}->get( "vm_spec", "host_spec" ) ) unless defined $answer;

    # convert the HTML answer to pure json
    $answer =~ s/<[^>]*>//gx;
    $answer =~ s/&quot;/"/gx;
    $answer =~ s/esx\.json//gx;
    # put the json structure to a perl data structure
    my $vm_spec = decode_json($answer);

    my $esx_host_and_datastore = $self->_get_esx_host_and_datastore($vm_spec);

    my @vms = (
        {
           vmname        => $self->{vm_name},
           vmhost        => $esx_host_and_datastore->{esx_host},
           datacenter    => $self->{config}->get( "vsphere", "datacenter" ),
           guestid       => $self->{guestid},
           datastore     => $esx_host_and_datastore->{esx_host_datastore},
           disksize      => $vm_spec->{virtualMachine}->{diskSize},
           memory        => $vm_spec->{virtualMachine}->{memory},
           num_cpus      => $vm_spec->{virtualMachine}->{numberOfProcessors},
           custom_fields => \%custom_fields,
           # Temporary deactivated (we using cmd or post data for this atm)
           #target_folder => $vm_spec->{virtualMachine}->{targetFolder},
           target_folder => $self->{vm_folder},
           has_frontend  => $vm_spec->{virtualMachine}->{hasFrontend},
           force_network => $self->{force_network},
        }
    );

    #print STDERR "DEBUG - VMproperties->generate_vms_array " . Data::Dumper->Dump( [ \@vms ] ) . "\n";

    return @vms;
}

sub print_usage {
    print _getUsageMessage();
}

#########################################
#########################################
#########################################
# private methods
#########################################
#########################################
#########################################

sub _get_esx_host_and_datastore {
    my ( $self, $resources ) = @_;

    my $esx_host = $self->{esx_host};
    my $esx_host_datastore;

    if ( !defined($esx_host) || $esx_host =~ qr(^auto_placement$) ) {
        my $result = $self->_get_esx_host_and_datastore_via_auto_placement($resources);
        $esx_host = $result->{esx_host};
        $esx_host_datastore = $result->{esx_host_datastore};;
        
    }
    else {
        # strip down the real hostname from given fqdn
        $esx_host =~ /(^[^\.]+).*$/x;
        my $esx_host_name = $1;

        $esx_host_datastore = $esx_host_name . ':datastore1';
    }

    return {
                   esx_host           => $esx_host,
                   esx_host_datastore => $esx_host_datastore,
    };
}

sub _get_esx_host_and_datastore_via_auto_placement {
    my ( $self, $resources ) = @_;
    my $esx_host;
    my $esx_host_datastore;

    my $vm_networks = new LML::VMnetworks( $self->{config} );
    my @required_network_labels = $vm_networks->find_network_labels( $self->{vm_name}, $self->{force_network} );

    my $vm_resources = new LML::VMresources(
        {
          ram      => $resources->{virtualMachine}->{memory},
          cpu      => $resources->{virtualMachine}->{numberOfProcessors},
          networks => \@required_network_labels,
          disks    => [ { size => $resources->{virtualMachine}->{diskSize} } ],    # we currently support only one disk
          name     => $self->{vm_name}
        }
    );

    #print STDERR "DEBUG - VMproperties->generate_vms_array->vm_resources " . Data::Dumper->Dump( [ \$vm_resources ] ) . "\n";

    my $vm_placement = new LML::VMplacement( $self->{config}, $self->{lab} );
    my @recommendations = $vm_placement->get_recommendations($vm_resources);

    #print STDERR "DEBUG - VMproperties->generate_vms_array->recommendations " . Data::Dumper->Dump( [ \@recommendations ] ) . "\n";

    if (@recommendations) {
        my $recommended_esx_id           = $recommendations[0]->{id};
        my $recommended_esx_datastore_id = $recommendations[0]->{datastores}[0];    # take the first datastore
        $esx_host = $self->{lab}->{ESXHOSTS}{$recommended_esx_id}{name};            # find name for id

        if ( $recommendations[0]->{datastores} ) {
            $esx_host_datastore = $self->{lab}->{DATASTORES}{$recommended_esx_datastore_id}{name};
        }
        else {
            #$esx_host_datastore = ???; TODO: this has still to be implemented to be handle by vm_create.pl
            $self->_error("VM creation without at least one disk is currently not supported.");
        }
    }
    else {
        $self->_error("Recommendation for automatic placement failed.");
    }
    
    return {esx_host => $esx_host, esx_host_datastore => $esx_host_datastore};
}

sub _getUsageMessage {
    return "vm-create.pl <OPTIONS>\n\n" . "   --name=value \t\t Name of the vm to be created (e.g. devxyz01)\n" . "   --username=value \t\t Name of the user, which is responsible for the vm (e.g. lmueller)\n" . "   --expiration=value \t\t Date where the vm will be expired (e.g. 01.01.2015) \n" . "   --esx_host=value \t\t FQDN of the ESX host where the vm should be created\n" . "   --folder=value \t\t VM folder name, where the vm should be placed\n" . "   --force_network=label \t OPTIONAL: Network which the new VM should be attached\n" . "   --force_boot=value \t\t Force boot value for the new vm\n\n";
}

# check the validity of the given paramter
# ========================================
sub _check_parameter {
    # expected args vm_name, username, expiration_date
    my ( $class, $C, %args ) = @_;
    my $result = "";

    # Check Expiration-Date
    my $european = $C->get( "vsphere", "expires_european" );
    $result = $result . "invalid expiration_date" . $/
      if ( !$args{expiration_date} or !eval { DateTime::Format::Flexible->parse_datetime( $args{expiration_date}, european => $european ) } );

    # Check VM-Name
    my $hostname_pattern = $C->get( "hostrules", "pattern" );
    $result = $result . "invalid vm_name" . $/ if ( !$args{vm_name} or $args{vm_name} !~ m/($hostname_pattern)/x );

    # Check User-Name
    unless ( exists $args{is_test_mode} ) {
        my $contactuserid_minuid = $C->get( "vsphere", "contactuserid_minuid" );
        my @pwnaminfo;
        @pwnaminfo = getpwnam $args{username} if ( $args{username} );
        $result = $result . "invalid username" . $/ if ( !scalar @pwnaminfo or $pwnaminfo[2] < $contactuserid_minuid );
    }
    # TODO: Check force_boot_target

    # TODO: Check the validity of given esx host

    # TODO: Check if folder is given

    # give result
    return $result;
}

# compose error output related to the execution context
# =====================================================
sub _error {
    my ( $ignore, $message ) = @_;    # could be called as a class or instance method - we don't care...

    # print html header before anything else if CGI is used
    if ( exists $ENV{GATEWAY_INTERFACE} ) {
        print header( -status => '500 Error while processing' );
        print $message;
    }

    #Util::disconnect();

    die $message . "\n" . _getUsageMessage();
}

1;
