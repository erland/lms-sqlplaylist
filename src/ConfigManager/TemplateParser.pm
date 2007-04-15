# 			ConfigManager::TemplateParser module
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

package Plugins::SQLPlayList::ConfigManager::TemplateParser;

use strict;
use Plugins::SQLPlayList::ConfigManager::BaseParser;
our @ISA = qw(Plugins::SQLPlayList::ConfigManager::BaseParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub new {
	my $class = shift;
	my $parameters = shift;

	$parameters->{'contentType'} = 'template';
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
	
	my %localcontext = ();
	if($globalcontext->{'source'} ne 'plugin') {
		return $self->parseContent($client,$item,$content,$items,$globalcontext,\%localcontext);
	}else {
		$items->{$item} = $content;
		return undef;
	}
}

sub checkContent {
	my $self = shift;
	my $xml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	if(defined($xml->{'downloadidentifier'})) {
		$localcontext->{'downloadidentifier'} = $xml->{'downloadidentifier'};
	}
	if($globalcontext->{'source'} ne 'plugin' && $globalcontext->{'source'} ne 'builtin') {
		$xml->{'template'}->{'customtemplate'} = 1;
	}
	return 1;
}
1;

__END__
