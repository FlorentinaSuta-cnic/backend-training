#!/usr/bin/perl -w
#
# (c)2016 HEXONET GmbH, 66424 Homburg, Germany
#

use strict;

$| = 1;

use RegistryClient::HEXONET;

my $registryhandler = new RegistryClient::HEXONET ();

framework::ready(1);
framework::registryhandler($registryhandler);

1;

