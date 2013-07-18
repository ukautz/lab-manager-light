#!/usr/bin/perl -w

# required RPM dependencies on RHEL/compatible:
# zbar
# perl-libwww-perl
# perl-JSON
# perl-DateTime

# Defaults
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/lib";

# Our test modules
use TestTools::VMmanager;
use TestTools::VmCreateOptions;

# For debugging
use Data::Dumper;

#

my $vm_create_options = new TestTools::VmCreateOptions(
                                                    vm_name_prefix    => 'devxxx',
                                                    username          => 'webadmin',
                                                    esx_host          => 'tuvesx04.dev.is24.loc',
                                                    test_host         => 'devnic01.rz.is',
                                                    lmlhostpattern    => 'devnic',
                                                    vm_folder         => '/Infrastructure/Integration-Tests',
);

my $vm_manager = new TestTools::VMmanager($vm_create_options);

my $vm_created = $vm_manager->create_vm();

my $qr_data = $vm_created->load_qrdata();

#print "DEBUG-HOST: " . $qr_data->{vm_created}->{HOST} . "\n";
#print "DEBUG1: ".Data::Dumper->Dump([%{$qr_data->{vm_created}}])."\n";

$qr_data->assert_qr_code_age();
$qr_data->assert_vm_path();
$qr_data->assert_lml_host();
$qr_data->assert_uuid();
$qr_data->assert_host();
$qr_data->assert_hostname();
$qr_data->assert_contact_user_id();
$qr_data->assert_expiration_date();

$vm_manager->delete_vm();
print "##teamcity[buildStatus status='SUCCESS' text='Integration Test OK']" . $/;

END {
    $vm_manager->delete_vm();
}
