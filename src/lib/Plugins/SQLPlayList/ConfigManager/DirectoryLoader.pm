# 			ConfigManager::DirectoryLoader code
#
#    Copyright (c) 2006-2007 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::SQLPlayList::ConfigManager::DirectoryLoader;

use strict;

use base 'Class::Data::Accessor';

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use FindBin qw($Bin);
use Cache::Cache qw( $EXPIRES_NEVER);

__PACKAGE__->mk_classaccessors( qw(logHandler extension includeExtensionInIdentifier identifierExtension parser cacheName cache cacheItems) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'logHandler' => $parameters->{'logHandler'},
		'extension' => $parameters->{'extension'},
		'identifierExtension' => $parameters->{'identifierExtension'},
		'includeExtensionInIdentifier' => $parameters->{'includeExtensionInIdentifier'},
		'parser' => $parameters->{'parser'},
		'cacheName' => $parameters->{'cacheName'},
		'cache' => undef,
	};
	$self->{'cacheItems'} = undef;
	if(defined($self->{'cacheName'})) {
		$self->{'cache'} = Slim::Utils::Cache->new($self->{'cacheName'})
	}

	bless $self,$class;
	return $self;
}

sub readFromCache {
	my $self = shift;

	if(defined($self->cacheName) && defined($self->cache)) {
		$self->cacheItems($self->cache->get($self->cacheName));
		if(!defined($self->cacheItems)) {
			my %noItems = ();
			my %empty = (
				'items' => \%noItems,
				'timestamp' => undef,
			);
			$self->cacheItems(\%empty);
		}
	}
	if(defined($self->parser)) {
		$self->parser->readFromCache();
	}
}

sub writeToCache {
	my $self = shift;

	if(defined($self->cacheName) && defined($self->cache) && defined($self->cacheItems)) {
		$self->cacheItems->{'timestamp'} = time();
		$self->cache->set($self->cacheName,$self->cacheItems,$EXPIRES_NEVER);
	}
	if(defined($self->parser)) {
		$self->parser->writeToCache();
	}
}

sub readFromDir {
	my $self = shift;
	my $client = shift;
	my $dir = shift;
	my $items = shift;
	my $globalcontext = shift;

	$self->logHandler->debug("Loading configuration from: $dir\n");
	$self->readFromCache();
	my @dircontents = Slim::Utils::Misc::readDirectory($dir,$self->extension);
	my $extensionRegexp = "\\.".$self->extension."\$";
	for my $item (@dircontents) {
		next unless $item =~ /$extensionRegexp/;
		next if -d catdir($dir, $item);

		my $path = catfile($dir, $item);

		my $extension = $self->extension;
		$extension =~ s/\./\\./;
		$extension = ".".$extension."\$";
		if(!defined($self->includeExtensionInIdentifier) || !$self->includeExtensionInIdentifier) {
			$item =~ s/$extension//;
		}

		my $timestamp = (stat ($path) )[9];

		# read_file from File::Slurp
		my $content = undef;
		if(defined($self->cacheItems) && defined($self->cacheItems->{'items'}->{$path}) && defined($timestamp) && $self->cacheItems->{'items'}->{$path}->{'timestamp'}>=$timestamp) {
			#$self->logHandler->debug("Reading $item from cache\n");
			$content = $self->cacheItems->{'items'}->{$path}->{'data'};
		}else {
			$content = eval { read_file($path) };
			if ( $content ) {
				my $encoding = Slim::Utils::Unicode::encodingFromString($content);
				if($encoding ne 'utf8') {
					$content = Slim::Utils::Unicode::latin1toUTF8($content);
					$content = Slim::Utils::Unicode::utf8on($content);
					$self->logHandler->debug("Loading $item and converting from latin1\n");
				}else {
					$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
					$self->logHandler->debug("Loading $item without conversion with encoding ".$encoding."\n");
				}
			}
		}
		if ( $content ) {
			if(defined($self->cacheItems) && defined($timestamp)) {
				my %entry = (
					'data' => $content,
					'timestamp' => $timestamp
				);
				delete $self->cacheItems->{'items'}->{$path};
				$self->cacheItems->{'items'}->{$path} = \%entry;
			}
			if(defined($self->parser)) {
				my %localcontext = ();
				if(defined($timestamp)) {
					$localcontext{'timestamp'} = $timestamp;
				}
				$localcontext{'cacheNamePrefix'} = $dir.$self->extension;
	                	$self->logHandler->debug("Parsing file: $path\n");
				my $errorMsg = $self->parser->parse($client,$item,$content,$items,$globalcontext,\%localcontext);
				if($errorMsg) {
		                	$self->logHandler->warn("Unable to open file: $path\n$errorMsg\n");
				}
			}
		}else {
			if ($@) {
				$self->logHandler->warn("Unable to open file: $path\nBecause of:\n$@\n");
			}else {
				$self->logHandler->warn("Unable to open file: $path\n");
			}
		}
	}
	$self->writeToCache();
}

sub readDataFromDir {
	my $self = shift;
	my $dir = shift;
	my $itemId = shift;

	my $file = $itemId;
	if($self->includeExtensionInIdentifier) {
		my $regExp = "\.".$self->identifierExtension."\$";
		$regExp =~ s/\./\\./g;
		$file =~ s/$regExp//;
		$file .= ".".$self->extension;
	}else {
		$file .= ".".$self->extension;
	}

	$self->logHandler->debug("Loading item data from: $dir/$file\n");

	my $path = catfile($dir, $file);
    
	return unless -f $path;

	my $timestamp = (stat ($path) )[9];
	if(defined($self->cacheItems) && defined($self->cacheItems->{'items'}->{$path}) && defined($timestamp) && $self->cacheItems->{'items'}->{$path}->{'timestamp'}>=$timestamp) {
		#$self->logHandler->debug("Reading $item from cache\n");
		return $self->cacheItems->{'items'}->{$path}->{'data'};
	}

	my $content = eval { read_file($path) };
	if ($@) {
		$self->logHandler->warn("Failed to load item data because:\n$@\n");
	}
	if(defined($content)) {
		my $encoding = Slim::Utils::Unicode::encodingFromString($content);
		if($encoding ne 'utf8') {
			$content = Slim::Utils::Unicode::latin1toUTF8($content);
			$content = Slim::Utils::Unicode::utf8on($content);
			$self->logHandler->debug("Loading $itemId and converting from latin1 to $encoding\n");
		}else {
			$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
			$self->logHandler->debug("Loading $itemId without conversion with encoding ".$encoding."\n");
		}
		if(defined($timestamp) && defined($self->cacheItems)) {
			my %entry = (
				'data' => $content,
				'timestamp' => $timestamp,
			);
			$self->cacheItems->{'items'}->{$path} = \%entry;
		}
		$self->logHandler->debug("Loading of item data succeeded\n");
	}
	return $content;
}

1;

__END__
