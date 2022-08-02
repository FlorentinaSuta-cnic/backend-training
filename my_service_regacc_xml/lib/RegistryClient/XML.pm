
package RegistryClient::XML;

use strict;

use XML::LibXML;
use utf8;

require "/opt/common/perl/lib/timeconv2.pl";

sub new {	
	my $class = shift;
	my $self = {};
	
	if ( @_ ) {
		$self = {@_};
	}
	
	$self->{commands} = {};
	
	return bless $self, $class;
}


sub registerCommand {
	my $self = shift;
	my $command_name = uc shift;
	my $function = shift;
	
	$self->{commands}{$command_name} = $function;
}


sub executeCommand {
	my $self = shift;
	my $command_hash = shift;
	my $command_name = uc $command_hash->{COMMAND};
	my $function = $self->{commands}{$command_name};
	$function = $self->{commands}{"*"} if !defined $function;
	if ( !defined $function ) {
		$function = sub {
			my $command = shift;
			my $callback = shift;
			my $response = {
				CODE => 500,
				DESCRIPTION => "Invalid command name: $command_name"
			};
			return &$callback($response);
		};
	}
	@_ = (sub {return shift;}) unless @_;
	return &$function($command_hash, @_);
}


sub textFromDOM {
	my $self = shift;
	my $node = shift;
	my $namespace = shift;
	my $tag = shift;
	my $aname = shift;
	my $avalue = shift;
	
	my @nodes = $node->getElementsByTagNameNS($namespace, $tag);
	my @texts = ();
	
	foreach my $n ( @nodes ) {
		if ( defined $aname ) {
			my $v = $n->getAttribute($aname);
			next if !defined $v;
			if ( defined $avalue ) {
				next if $avalue ne $v;
			}
		}
		push @texts, $n->textContent();
	}
	
	if ( !wantarray ) {
		die "Found more than 1 node!"
			if $#texts > 0;
		return undef if !@texts;
		return $texts[0];
	}
	
	return @texts;
}


sub textToDOM {
	# replace text content
	my $self = shift;
	my $node = shift;
	my $namespace = shift;
	my $tag = shift;
	my $aname = shift;
	my $avalue = shift;
	my $old_data = shift;
	my $new_data = shift;

	return undef
		if !defined $old_data || !defined $new_data;

	my $changes = 0;

	foreach my $n ( $node->getElementsByTagNameNS($namespace, $tag) ) {
		# limit operation to elements with a dedicated attribute and value, if requested:
		if ( defined $aname ) {
			my $v = $n->getAttribute($aname);
			next if !defined $v;
			if ( defined $avalue ) {
				next if $avalue ne $v;
			}
		}

		foreach my $childnode ( $n->childNodes() ) {
			next
				if $childnode->nodeType != 3; # XML_TEXT_NODE => 3;
			if ( $childnode->data && $childnode->data eq $old_data ) {
				$childnode->setData($new_data);
				$changes++;
			}
		}
	}

	return $changes;
}


sub dateFromDOM {
	my $self = shift;
	my @texts = $self->textFromDOM(@_);
	my @dates = ();
	foreach my $date ( @texts ) {
		next if (!defined $date) || (!length $date);

		$date =~ s/T/ /i;
		if ( $date =~ s/Z$//i ) {
		}
		else {
# CORRECT NON-UTC TimeStamps
			$date = sqltime(timesql($date));
		}
		push @dates, $date;
	}
	if ( !wantarray ) {
		die "Found more than 1 node!"
			if $#dates > 0;
		return undef if !@dates;
		return $dates[0];
	}
	return @dates;
}


sub createNSAttributeHash {
	my $self = shift;
	my $namespace = shift;
	my $prefix = shift;
	$prefix = "" if !defined $prefix;

	my $location = $namespace;
	$location = "$1.xsd"
		if $location =~ /[:\/]([^:\/]+)$/;
	if ( length($prefix) ) {
#		print STDERR "createNSAttributeHash($namespace, $prefix)\n";
		return {
			"xmlns:$prefix" => $namespace,
			"xsi:schemaLocation" => "$namespace $location"
		};
	}
	my $attr = {
		"xmlns:$prefix" => $namespace,
		"xsi:schemaLocation" => [
			"http://www.w3.org/2001/XMLSchema-instance",
			"$namespace $location"
		],
	};
	return $attr;
}


sub createXMLFromHash {
	my $self = shift;
	return $self->createXMLFromDOM($self->createDOMFromHash(@_));
}

sub createDOMFromHash {
	my $self = shift;
	my $input = shift;
	my $doc = shift;
	my $element = shift;
	$doc = $self->createDOM() if !defined $doc;
	return $element if !defined $input;
	if ( !ref $input ) {
		my $node = $doc->createTextNode($input);
		$element->appendChild($node);
		return $element;
	}
	my @l = @{$input};
	return $element if !@l;
	my $name = shift @l;
	my $node = $doc->createElement($name);
	
	if ( defined $element ) {
		$element->appendChild($node);
	}
	else {
		$doc->setDocumentElement( $node );
	}
	
	if ( @l ) {
		my @e = ();
		foreach my $e ( @l ) {
			if ( ref $e eq "HASH" ) {
				foreach my $a ( sort keys %{$e} ) {
					my $v = $e->{$a};
					if ( ref $v eq "ARRAY" ) {
						$node->setAttributeNS($v->[0], $a, $v->[1]);
					}
					else {
#						print STDERR "$a -> " . $e->{$a} . "\n";
						$node->setAttribute($a, $e->{$a});
					}
				}
			}
			else {
				push @e, $e;
			}
		}
		foreach my $e ( @e ) {
			$self->createDOMFromHash($e, $doc, $node);
		}
	}
	return $element if defined $element;
	return $doc;
}


sub createDOM {
	my $self = shift;
	my $doc = XML::LibXML::Document->new("1.0", "UTF-8");
	$doc->setStandalone(0);
	return $doc;
}

sub createXMLFromDOM {
	my $self = shift;
	my $doc = shift;
	my $string = $doc->serialize(0);
	if ( utf8::is_utf8($string) ) {
		utf8::encode($string);
	}
	return $string;
}


sub createDOMFromString {
	my $self = shift;
	my $string = shift;
	$string =~ s/\s+\</\</og;
	$string =~ s/\>\s+/\>/og;
	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($string);
	return $doc;
}





package _xml;

use strict;


# BEGIN OF libxml specific stuff

sub string_from_dom {
	my $doc = shift;
#	my $string = $doc->serialize(1);
	my $string = $doc->serialize(0);
	if ( utf8::is_utf8($string) ) {
		utf8::encode($string);
	}
	return $string;
}


sub pretty_string {
	my $doc = shift;
	$doc = dom_from_string($doc) if !ref $doc;
	my $string = $doc->serialize(1);
	if ( utf8::is_utf8($string) ) {
		utf8::encode($string);
	}
	return $string;
}


sub dom_create_document {
	my $doc = XML::LibXML::Document->new("1.0", "UTF-8");
	$doc->setStandalone(0);
	return $doc;
}


sub dom_from_string {
	my $string = shift;
	$string =~ s/\s+\</\</og;
	$string =~ s/\>\s+/\>/og;
	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($string);
	return $doc;
}


# END OF libxml specific stuff


sub get_element_text {
	my $node = shift;
	my $namespace = shift;
	my $tag = shift;
	my $aname = shift;
	my $avalue = shift;
	
	my @nodes = $node->getElementsByTagNameNS($namespace, $tag);
	my @texts = ();
	
	foreach my $n ( @nodes ) {
		if ( defined $aname ) {
			my $v = $n->getAttribute($aname);
			next if !defined $v;
			if ( defined $avalue ) {
				next if $avalue ne $v;
			}
		}
		push @texts, $n->textContent();
	}
	
	if ( !wantarray ) {
		die "Found more than 1 node!"
			if $#texts > 0;
		return undef if !@texts;
		return $texts[0];
	}
	
	return @texts;
}


sub string_from_hash {
	return string_from_dom(dom_from_hash(@_));
}


sub dom_from_hash {
	my $input = shift;
	my $doc = shift;
	my $element = shift;
	$doc = dom_create_document() if !defined $doc;
	return $element if !defined $input;
	if ( !ref $input ) {
		my $node = $doc->createTextNode($input);
		$element->appendChild($node);
		return $element;
	}
	my @l = @{$input};
	return $element if !@l;
	my $name = shift @l;
	my $node = $doc->createElement($name);
	
	if ( defined $element ) {
		$element->appendChild($node);
	}
	else {
		$doc->setDocumentElement( $node );
	}
	
	if ( @l ) {
		my @e = ();
		foreach my $e ( @l ) {
			if ( ref $e eq "HASH" ) {
				foreach my $a ( sort keys %{$e} ) {
					my $v = $e->{$a};
					if ( ref $v eq "ARRAY" ) {
						$node->setAttributeNS($v->[0], $a, $v->[1]);
					}
					else {
						$node->setAttribute($a, $e->{$a});
					}
				}
			}
			else {
				push @e, $e;
			}
		}
		foreach my $e ( @e ) {
			dom_from_hash($e, $doc, $node);
		}
	}
	return $element if defined $element;
	return $doc;
}



sub namespace_attributes_hash {
	my $namespace = shift;
	my $prefix = shift;
	$prefix = "" if !defined $prefix;
	my $location = $namespace;
	$location = "$1.xsd"
		if $location =~ /[:\/]([^:\/]+)$/;
	if ( length($prefix) ) {
#		print STDERR "namespace_attributes_hash($namespace, $prefix)\n";
		return {
			"xmlns:$prefix" => $namespace,
			"xsi:schemaLocation" => "$namespace $location"
		};
	}
	my $attr = {
		"xmlns:$prefix" => $namespace,
		"xsi:schemaLocation" => [
			"http://www.w3.org/2001/XMLSchema-instance",
			"$namespace $location"
		],
	};
	return $attr;
}



1;
