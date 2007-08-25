# 			ConfigManager::ContentParser module
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package Plugins::SQLPlayList::ConfigManager::ContentParser;

use strict;
use base 'Class::Data::Accessor';
use Plugins::SQLPlayList::ConfigManager::BaseParser;
our @ISA = qw(Plugins::SQLPlayList::ConfigManager::BaseParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub new {
	my $class = shift;
	my $parameters = shift;

	$parameters->{'contentType'} = 'playlist';
	my $self = $class->SUPER::new($parameters);
	bless $self,$class;
	return $self;
}

sub parse {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	return $self->parseContent($client,$item,$content,$items,$globalcontext,$localcontext);
}

sub parseContentImplementation {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	my $errorMsg = undef;
        if ( $content ) {

		my @playlistDataArray = split(/[\n\r]+/,$content);
		my $name = undef;
		my $statement = '';
		my $fulltext = '';
		my @groups = ();
		my %parameters = ();
		my %options = ();
		my %startactions = ();
		my %stopactions = ();
		for my $line (@playlistDataArray) {
			#Lets add linefeed again, to make sure playlist looks ok when editing
			$line .= "\n";
			if($name && $line !~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
				$fulltext .= $line;
			}
			chomp $line;
	
			# use "--PlaylistName:" as name of playlist
			$line =~ s/^\s*--\s*PlaylistName\s*[:=]\s*//io;
			
			my $parameter = $self->parseParameter($line);
			my $action = $self->parseAction($line);
			my $option = $self->parseOption($line);
			if($line =~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
				$line =~ s/^\s*--\s*PlaylistGroups\s*[:=]\s*//io;
				if($line) {
					my @stringGroups = split(/\,/,$line);
					foreach my $group (@stringGroups) {
						# Remove all white spaces
						$group =~ s/^\s+//;
						$group =~ s/\s+$//;
						my @subGroups = split(/\//,$group);
						push @groups,\@subGroups;
					}
				}
				$line = "";
			}
			if($parameter) {
				$parameters{$parameter->{'id'}} = $parameter;
			}
			if($option) {
				$options{$option->{'id'}} = $option;
			}
			if($action) {
				if($action->{'execute'} eq 'Start') {
					$startactions{$action->{'id'}} = $action;
				}elsif($action->{'execute'} eq 'Stop') {
					$stopactions{$action->{'id'}} = $action;
				}
			}
				
			# skip and strip comments & empty lines
			$line =~ s/\s*--.*?$//o;
			$line =~ s/^\s*//o;
	
			next if $line =~ /^--/;
			next if $line =~ /^\s*$/;
	
			if(!$name) {
				$name = $line;
			}else {
				$line =~ s/\s+$//;
				if($statement) {
					if( $statement =~ /;$/ ) {
						$statement .= "\n";
					}else {
						$statement .= " ";
					}
				}
				$statement .= $line;
			}
		}
	
		if($name && $statement) {
			#my $playlistid = escape($name,"^A-Za-z0-9\-_");
			my $playlistid = $item;
			my $file = $item;
			if($globalcontext->{'source'} ne "plugin") {
				$file = $item.".sql";
			}
			my %playlist = (
				'id' => $playlistid, 
				'file' => $file,
				'name' => $name, 
				'sql' => Slim::Utils::Unicode::utf8decode($statement,'utf8') , 
				'fulltext' => Slim::Utils::Unicode::utf8decode($fulltext,'utf8')
			);
			if($globalcontext->{'source'} eq "builtin" || $globalcontext->{'source'} eq "plugin") {
				$playlist{'defaultplaylist'} = 1;
			}else {
				$playlist{'customplaylist'} = 1;
			}
	
			if(defined($localcontext) && defined($localcontext->{'downloadidentifier'})) {
				$playlist{'downloadedplaylist'} = 1;
			}
			if(defined($localcontext) && defined($localcontext->{'simple'})) {
				$playlist{'simple'} = 1;
			}
			if(scalar(@groups)>0) {
				$playlist{'groups'} = \@groups;
			}
			if(%parameters) {
				$playlist{'parameters'} = \%parameters;
				my $playLists = $items;
				foreach my $p (keys %parameters) {
					if(defined($playLists) 
						&& defined($playLists->{$playlistid}) 
						&& defined($playLists->{$playlistid}->{'parameters'})
						&& defined($playLists->{$playlistid}->{'parameters'}->{$p})
						&& $playLists->{$playlistid}->{'parameters'}->{$p}->{'name'} eq $parameters{$p}->{'name'}
						&& defined($playLists->{$playlistid}->{'parameters'}->{$p}->{'value'})) {
						
						debugMsg("Use already existing value PlaylistParameter$p=".$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'}."\n");	
						$parameters{$p}->{'value'}=$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'};
					}
				}
			}
			if(%options) {
				$playlist{'options'} = \%options;
			}
			if(%startactions) {
				my @actionArray = ();
				for my $key (keys %startactions) {
					my $a = $startactions{$key};
					push @actionArray,$a;
				}
				$playlist{'startactions'} = \@actionArray;
			}
			if(%stopactions) {
				my @actionArray = ();
				for my $key (keys %stopactions) {
					my $a = $stopactions{$key};
					push @actionArray,$a;
				}
				$playlist{'stopactions'} = \@actionArray;
			}
	                return \%playlist;
		}

	}else {
		if ($@) {
			$errorMsg = "Incorrect information in playlist data: $@";
			$self->errorCallback->("Unable to read playlist configuration:\n$@\n");
		}else {
			$errorMsg = "Incorrect information in playlist data";
			$self->errorCallback->("Unable to to read playlist configuration\n");
		}
	}
	return undef;
}

sub parseParameter {
	my $self = shift;
	my $line = shift;
	
	if($line =~ /^\s*--\s*PlaylistParameter\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistParameter\s*(\d)\s*[:=]\s*([^:]+):\s*([^:]*):\s*(.*)$/;
		my $parameterId = $1;
		my $parameterType = $2;
		my $parameterName = $3;
		my $parameterDefinition = $4;

		$parameterType =~ s/^\s+//;
		$parameterType =~ s/\s+$//;

		$parameterName =~ s/^\s+//;
		$parameterName =~ s/\s+$//;

		$parameterDefinition =~ s/^\s+//;
		$parameterDefinition =~ s/\s+$//;

		if($parameterId && $parameterName && $parameterType) {
			my %parameter = (
				'id' => $parameterId,
				'type' => $parameterType,
				'name' => $parameterName,
				'definition' => $parameterDefinition
			);
			return \%parameter;
		}else {
			$self->debugCallback->("Error in parameter: $line\n");
			$self->debugCallback->("Parameter values: Id=$parameterId, Type=$parameterType, Name=$parameterName, Definition=$parameterDefinition\n");
			return undef;
		}
	}
	return undef;
}	

sub parseAction {
	my $self = shift;
	my $line = shift;
	my $actionType = shift;
	
	if($line =~ /^\s*--\s*Playlist(Start|Stop)Action\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*Playlist(Start|Stop)Action\s*(\d)\s*[:=]\s*([^:]+):\s*(.*)$/;
		my $executeTime = $1;
		my $actionId = $2;
		my $actionType = $3;
		my $actionDefinition = $4;

		$actionType =~ s/^\s+//;
		$actionType =~ s/\s+$//;

		$actionDefinition =~ s/^\s+//;
		$actionDefinition =~ s/\s+$//;

		if($actionId && $actionType && $actionDefinition) {
			my %action = (
				'id' => $actionId,
				'execute' => $executeTime,
				'type' => $actionType,
				'data' => $actionDefinition
			);
			return \%action;
		}else {
			$self->debugCallback->("Error in action: $line\n");
			$self->debugCallback->("Action values: Id=$actionId, Type=$actionType, Definition=$actionDefinition\n");
			return undef;
		}
	}
	return undef;
}	

sub parseOption {
	my $self = shift;
	my $line = shift;
	if($line =~ /^\s*--\s*PlaylistOption\s*[^:=]+\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistOption\s*([^:=]+)\s*[:=]\s*(.+)\s*$/;
		my $optionId = $1;
		my $optionValue = $2;

		$optionId =~ s/\s+$//;

		$optionValue =~ s/^\s+//;
		$optionValue =~ s/\s+$//;

		if($optionId && $optionValue) {
			my %option = (
				'id' => $optionId,
				'value' => $optionValue
			);
			return \%option;
		}else {
			$self->debugCallback->("Error in option: $line\n");
			$self->debugCallback->("Option values: Id=$optionId, Value=$optionValue\n");
			return undef;
		}
	}
	return undef;
}	

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;
1;

__END__
