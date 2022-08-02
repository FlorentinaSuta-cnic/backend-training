
sub execCommand_DefaultFallback {
	my $user = shift;
	my $command = shift;

	return registryhandler->executeCommand($command, sub { return shift; } );
}

1;
