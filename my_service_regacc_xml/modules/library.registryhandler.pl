
my $registryhandler;

sub registryhandler {
	if ( @_ ) {
		$registryhandler = shift;
	}
	return $registryhandler;
}

sub doRegistryCommand {
	my $command = shift;
	
}






1;
