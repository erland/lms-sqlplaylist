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

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback extension includeExtensionInIdentifier parser) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'extension' => $parameters->{'extension'},
		'includeExtensionInIdentifier' => $parameters->{'includeExtensionInIdentifier'},
		'parser' => $parameters->{'parser'}
	};
	bless $self,$class;
	return $self;
}

sub readFromDir {
	my $self = shift;
	my $client = shift;
	my $dir = shift;
	my $items = shift;
	my $globalcontext = shift;

	$self->debugCallback->("Loading configuration from: $dir\n");

	my @dircontents = Slim::Utils::Misc::readDirectory($dir,$self->extension);
	my $extensionRegexp = "\\.".$self->extension."\$";
	for my $item (@dircontents) {

		next unless $item =~ /$extensionRegexp/;
		next if -d catdir($dir, $item);

		my $path = catfile($dir, $item);
		# read_file from File::Slurp
		my $content = eval { read_file($path) };
		if ( $content ) {
			if(defined($self->parser)) {
				my $extension = $self->extension;
				$extension =~ s/\./\\./;
				$extension = ".".$extension."\$";
				if(!defined($self->includeExtensionInIdentifier) || !$self->includeExtensionInIdentifier) {
					$item =~ s/$extension//;
				}
				my $errorMsg = $self->parser->parse($client,$item,$content,$items,$globalcontext);
				if($errorMsg) {
		                	$self->errorCallback->("Unable to open file: $path\n$errorMsg\n");
				}
			}
		}else {
			if ($@) {
				$self->errorCallback->("Unable to open file: $path\nBecause of:\n$@\n");
			}else {
				$self->errorCallback->("Unable to open file: $path\n");
			}
		}
	}
}

sub readDataFromDir {
	my $self = shift;
	my $dir = shift;
	my $itemId = shift;

	my $file = $itemId.".".$self->extension;
	$self->debugCallback->("Loading item data from: $dir/$file\n");

	my $path = catfile($dir, $file);
    
	return unless -f $path;

	my $content = eval { read_file($path) };
	if ($@) {
		$self->debugCallback->("Failed to load item data because:\n$@\n");
	}
	if(defined($content)) {
		$self->debugCallback->("Loading of item data succeeded\n");
	}
	return $content;
}

1;

__END__
