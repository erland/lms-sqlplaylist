# 			ConfigManager::PluginLoader code
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

package Plugins::SQLPlayList::ConfigManager::PluginLoader;

use strict;

use base 'Class::Data::Accessor';

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Data::Dumper;

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback listMethod dataMethod pluginId contentType templateContentParser contentParser) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'listMethod' => $parameters->{'listMethod'},
		'dataMethod' => $parameters->{'dataMethod'},
		'pluginId' => $parameters->{'pluginId'},
		'contentType' => $parameters->{'contentType'},
		'contentParser' => $parameters->{'contentParser'},
		'templateContentParser' => $parameters->{'templateContentParser'}
	};
	bless $self,$class;
	return $self;
}

sub readFromPlugins {
	my $self = shift;
	my $client = shift;
	my $items = shift;
	my $excludePlugins = shift;
	my $globalcontext = shift;

	no strict 'refs';
	my @enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
	
	my %excludePluginsHash = ();
	if($excludePlugins) {
		my @items = split(/\,/,$excludePlugins);
		for my $item (@items) {
			$excludePluginsHash{$item} = 1;
		}
	}
	for my $plugin (@enabledplugins) {
		if($excludePluginsHash{$plugin}) {
			next;
		}
		if(UNIVERSAL::can("Plugins::$plugin",$self->listMethod)) {
			$self->debugCallback->("Calling ".$self->listMethod." for: $plugin\n");
			my $pluginItems = eval { &{"Plugins::${plugin}::".$self->listMethod}($client) };
			if ($@) {
				$self->debugCallback->("Error calling ".$self->listMethod." from $plugin: $@\n");
			}
			$self->debugCallback->("Got ".scalar(@$pluginItems)." items from $plugin\n");
			for my $item (@$pluginItems) {
				my $itemData = $item->{$self->contentType};
				my $itemId = $item->{'id'};
				$itemData->{'id'} = $item->{'id'};
				if($plugin =~ /^([^:]+)::.*$/) {
					$itemId = lc($1)."_".$item->{'id'};
				}
				if($item->{'type'} eq 'simple') {
					if(defined($self->templateContentParser)) {
						if(ref($itemData) ne 'HASH') {
							my $encoding = Slim::Utils::Unicode::encodingFromString($itemData);
							if($encoding ne 'utf8') {
								$itemData = Slim::Utils::Unicode::latin1toUTF8($itemData);
								$itemData = Slim::Utils::Unicode::utf8on($itemData);
								$self->debugCallback->("Loading $itemId configuration from $plugin and converting from latin1\n");
							}else {
								$itemData = Slim::Utils::Unicode::utf8decode($itemData,'utf8');
								$self->debugCallback->("Loading $itemId configuration from $plugin without conversion with encoding ".$encoding."\n");
							}
						}
						my $errorMsg = $self->templateContentParser->parse($client,$itemId,$itemData,$items,$globalcontext);
						if($errorMsg) {
		                			$self->errorCallback->("Unable to open plugin ".$self->contentType." configuration: $plugin(".$item->{'id'}.")\n$errorMsg\n");
						}elsif(defined($items->{$itemId})) {
							$items->{$itemId}->{'id'} = $itemId;
							$items->{$itemId}->{lc($self->pluginId).'_plugin_'.$self->contentType}=$item;
							$items->{$itemId}->{lc($self->pluginId).'_plugin'} = "Plugins::${plugin}";
						}
					}
				}else {
					my $errorMsg = undef;
					if(defined($self->contentParser)) {
						if(ref($itemData) ne 'HASH') {
							my $encoding = Slim::Utils::Unicode::encodingFromString($itemData);
							if($encoding ne 'utf8') {
								$itemData = Slim::Utils::Unicode::latin1toUTF8($itemData);
								$itemData = Slim::Utils::Unicode::utf8on($itemData);
								$self->debugCallback->("Loading $itemId configuration from $plugin and converting from latin1\n");
							}else {
								$itemData = Slim::Utils::Unicode::utf8decode($itemData,'utf8');
								$self->debugCallback->("Loading $itemId configuration from $plugin without conversion with encoding ".$encoding."\n");
							}
						}
						$errorMsg = $self->contentParser->parse($client,$itemId,$itemData,$items,$globalcontext);
					}
					if(defined($errorMsg)) {
	                			$self->errorCallback->("Unable to open plugin ".$self->contentType." configuration: $plugin(".$item->{'id'}.")\n$errorMsg\n");
					}else {
						if($plugin =~ /^([^:]+)::.*$/) {
							$itemId = lc($1)."_".$item->{'id'};
						}
						$items->{$itemId}->{'id'} = $itemId;
						$items->{$itemId}->{lc($self->pluginId).'_plugin_'.$self->contentType}=$item;
						$items->{$itemId}->{lc($self->pluginId).'_plugin'} = "Plugins::${plugin}";
					}
				}
			}
		}
	}
	use strict 'refs';
}

sub readDataFromPlugin {
	my $self = shift;
	my $client = shift;
	my $itemData = shift;
	my $parameters = shift;
	if(defined($itemData->{lc($self->pluginId).'_plugin'})) {
		my $content  = $self->_getPluginContentData($client,$itemData);
		if(defined($content) && ref($content) ne 'HASH') {
			my $encoding = Slim::Utils::Unicode::encodingFromString($content);
			if($encoding ne 'utf8') {
				$content = Slim::Utils::Unicode::latin1toUTF8($content);
				$content = Slim::Utils::Unicode::utf8on($content);
				$self->debugCallback->("Loading ".($itemData->{'id'}." data from ".$itemData->{lc($self->pluginId).'_plugin'})." and converting from latin1\n");
			}else {
				$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
				$self->debugCallback->("Loading ".($itemData->{'id'}." data from ".$itemData->{lc($self->pluginId).'_plugin'})." without conversion with encoding ".$encoding."\n");
			}
		}
		return $content;
	}
	return undef;
}

sub _getPluginContentData {
	my $self = shift;
	my $client = shift;
	my $itemData = shift;
	my $parameters = shift;

	my $plugin = $itemData->{lc($self->pluginId).'_plugin'};
	my $pluginItem = $itemData->{lc($self->pluginId).'_plugin_'.$self->contentType};
	my $itemFileData = undef;
	no strict 'refs';
	if(UNIVERSAL::can("$plugin",$self->dataMethod)) {
		$self->debugCallback->("Calling: $plugin :: ".$self->dataMethod."\n");
		$itemFileData =  eval { &{"${plugin}::".$self->dataMethod}($client,$pluginItem) };
		if ($@) {
			$self->debugCallback->("Error retreiving item data from $plugin: $@\n");
		}
	}
	use strict 'refs';
	return $itemFileData;
}
1;

__END__
