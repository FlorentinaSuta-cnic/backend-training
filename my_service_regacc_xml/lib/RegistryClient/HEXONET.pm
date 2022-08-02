
package RegistryClient::HEXONET;

use strict;

use RegistryClient::XML;
our @ISA = qw(RegistryClient::XML);


sub new {
	my $class = shift;
	my $self = new RegistryClient::XML(@_);
	bless $self, $class;

	$self->registerCommand("AddDomain", sub { $self->sendDomainCreate(@_); } );
	return $self;
}


sub sendDomainCreate {
	my $self = shift;
	my $command = shift;
	my $callback = shift;

	my $response = {
		CODE => 200,
		DESCRIPTION => "Command completed successfully"
	};

	return &$callback($response);
}


