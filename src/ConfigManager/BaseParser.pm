# 			ConfigManager::BaseParser code
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

package Plugins::SQLPlayList::ConfigManager::BaseParser;

use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use XML::Simple;
use Data::Dumper;
use HTML::Entities;
use Cache::Cache qw( $EXPIRES_NEVER);

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion contentType templateHandler cache cacheName cacheItems) );

my $utf8filenames = 1;
my $serverPrefs = preferences('server');
my $driver;
sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->contentType($parameters->{'contentType'});
	$self->cacheName($parameters->{'cacheName'});
	if(defined($self->cacheName)) {
		$self->cache(Slim::Utils::Cache->new($self->cacheName));
	}
	if(defined($parameters->{'utf8filenames'})) {
		$utf8filenames = $parameters->{'utf8filenames'};
	}
	#bless $self,$class;

	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;

	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

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
}

sub writeToCache {
	my $self = shift;

	if(defined($self->cacheName) && defined($self->cache) && defined($self->cacheItems)) {
		$self->cacheItems->{'timestamp'} = time();
		$self->cache->set($self->cacheName,$self->cacheItems,$EXPIRES_NEVER);
	}
}

sub parseContent {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	my $errorMsg = undef;
        if ( $content ) {
		my $result = eval { $self->parseContentImplementation($client,$item,$content,$items,$globalcontext,$localcontext) };
		if(!$@ && defined($result)) {
			my $timestamp = undef;
			if(defined($localcontext->{'timestamp'})) {
				$timestamp = $localcontext->{'timestamp'};
			}
			if(!defined($items->{$item}) || !defined($timestamp) || !defined($items->{$item}->{'timestamp'}) || $items->{$item}->{'timestamp'}<=$timestamp) {
				$self->logHandler->debug("Storing parsed result for $item\n");
				$items->{$item} = $result;
			}else {
				$self->logHandler->debug("Skipping $item, newer entry already loaded\n");
			}
		}else {
			$self->logHandler->debug("Skipping $item: $@\n");
			$errorMsg = "$@";
		}
		# Release content
		undef $content;
	}else {
		if ($@) {
			$errorMsg = "Incorrect information in data: $@";
			$self->logHandler->warn("Unable to read configuration:\n$@\n");
		}else {
			$errorMsg = "Incorrect information in data";
			$self->logHandler->warn("Unable to to read configuration\n");
		}
	}
	return $errorMsg;
}

sub parseTemplateContent {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $templates = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	my $cacheName = $item;
	if(defined($localcontext->{'cacheNamePrefix'})) {
		$cacheName = $localcontext->{'cacheNamePrefix'}.$cacheName;
	}

	my $dbh = getCurrentDBH();

	my $errorMsg = undef;
        if ( $content ) {
		my $timestamp = undef;
		if(defined($localcontext->{'timestamp'})) {
			$timestamp = $localcontext->{'timestamp'};
		}
		my $valuesXml = undef;
		if(defined($timestamp) && defined($self->cacheItems) && defined($self->cacheItems->{'items'}->{'values_'.$cacheName}) && $self->cacheItems->{'items'}->{'values_'.$cacheName}->{'timestamp'}>=$timestamp) {
			$valuesXml = $self->cacheItems->{'items'}->{'values_'.$cacheName}->{'data'};
		}else {
			$valuesXml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
			if(defined($timestamp) && defined($self->cacheItems)) {
				my %entry = (
					'data' => $valuesXml,
					'timestamp' => $timestamp,
				);
				delete $self->cacheItems->{'items'}->{'values_'.$cacheName};
				$self->cacheItems->{'items'}->{'values_'.$cacheName} = \%entry;
			}
		}
		#$self->logHandler->debug(Dumper($valuesXml));
		if ($@) {
			$errorMsg = "$@";
			$self->logHandler->warn("Failed to parse ".$self->contentType." configuration ($item) because:\n$@\n");
		}else {
			my $templateId = lc($valuesXml->{'template'}->{'id'});
			my $template = $templates->{$templateId};
			if(!defined($template)) {
				$self->logHandler->debug("Template $templateId not found\n");
				undef $content;
				return undef;
			}
			if(!$self->checkTemplateValues($template,$valuesXml,$globalcontext,$localcontext)) {
				$self->logHandler->debug("Ignoring $item due to checkTemplateValues\n");
				undef $content;
				return undef;
			}
			if(defined($template->{'timestamp'}) && defined($timestamp) && $template->{'timestamp'}>$timestamp) {
				$timestamp = $template->{'timestamp'};
				$localcontext->{'timestamp'} = $timestamp;
			}
			my $itemData = undef;
			if(defined($timestamp) && defined($self->cacheItems) && defined($self->cacheItems->{'items'}->{'templatecontent_'.$cacheName}) && $self->cacheItems->{'items'}->{'templatecontent_'.$cacheName}->{'timestamp'}>=$timestamp) {
				$itemData = $self->cacheItems->{'items'}->{'templatecontent_'.$cacheName}->{'data'};
			}else {
				my %templateParameters = ();
				my $parameters = $valuesXml->{'template'}->{'parameter'};
				my $notLibrarySupported = 0;
				for my $p (@$parameters) {
					my $values = $p->{'value'};
					if(!defined($values)) {
						my $tmp = $p->{'content'};
						if(defined($tmp)) {
							my @tmpArray = ($tmp);
							$values = \@tmpArray;
						}
					}
					my $value = '';
					for my $v (@$values) {
						if(ref($v) ne 'HASH') {
							if($value ne '') {
								$value .= ',';
							}
							if(!defined($p->{'rawvalue'}) || !$p->{'rawvalue'}) {
								if($driver eq 'SQLite') {
									$v =~ s/\'/\'\'/g;
								}else {
									$v =~ s/\\/\\\\/g;
									$v =~ s/\"/\\\"/g;
									$v =~ s/\'/\\\'/g;
								}
							}
							if($p->{'quotevalue'}) {
								$value .= "'".encode_entities($v,"&<>")."'";
							}else {
								$value .= encode_entities($v,"&<>");
							}
						}
					}
					#$self->logHandler->debug("Setting: ".$p->{'id'}."=".$value."\n");
					$templateParameters{$p->{'id'}}=$value;
				}
				my $librarySupported = 0;
				if(defined($template->{'parameter'})) {
					my $parameters = $template->{'parameter'};
					if(ref($parameters) ne 'ARRAY') {
						my @parameterArray = ();
						if(defined($parameters)) {
							push @parameterArray,$parameters;
						}
						$parameters = \@parameterArray;
					}
					for my $p (@$parameters) {
						if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
							if(!defined($templateParameters{$p->{'id'}})) {
								my $value = $p->{'value'};
								if(!defined($value) || ref($value) eq 'HASH') {
									my $tmp = $p->{'content'};
									if(defined($tmp)) {
										my @tmpArray = ($tmp);
										$value = \@tmpArray;
									}else {
										$value='';
									}
								}
								#$self->logHandler->debug("Setting default value ".$template->{'id'}." ".$p->{'id'}."=".$value."\n");
								$templateParameters{$p->{'id'}} = $value;
							}
							if(defined($p->{'requireplugins'})) {
								if(!isPluginsInstalled($client,$p->{'requireplugins'})) {
									$templateParameters{$p->{'id'}} = undef;
								}
							}
							if(defined($templateParameters{$p->{'id'}}))  {
								if(Slim::Utils::Unicode::encodingFromString($templateParameters{$p->{'id'}}) ne 'utf8') {
									$templateParameters{$p->{'id'}} = Slim::Utils::Unicode::latin1toUTF8($templateParameters{$p->{'id'}});
								}
							}
						}
					}
				}
				if(!$self->checkTemplateParameters($template,\%templateParameters,$globalcontext,$localcontext)) {
					$self->logHandler->debug("Ignoring $item due to checkTemplateParameters\n");
					undef $content;
					return undef;
				}
				addStandardParameters(\%templateParameters);
				my $templateData = $self->loadTemplate($client,$template,\%templateParameters);
				if(!defined($templateData)) {
					$self->logHandler->debug("Ignoring $item due to loadTemplate\n");
					undef $content;
					return undef;
				}
				my $templateFileData = $templateData->{'data'};
				my $doParsing = 1;
				if(!defined($templateData->{'parse'})) {
					$doParsing = 0;
				}
				
				if($doParsing) {
					$itemData = $self->fillTemplate($templateFileData,\%templateParameters);
				}else {
					$itemData = $templateFileData;
				}
				if(defined($timestamp) && defined($self->cacheItems)) {
					my %entry = (
						'data' => $itemData,
						'timestamp' => $timestamp,
					);
					delete $self->cacheItems->{'items'}->{'templatecontent_'.$cacheName};
					$self->cacheItems->{'items'}->{'templatecontent_'.$cacheName} = \%entry;
				}
			}
			my $result = eval {$self->parseContentImplementation($client,$item,$itemData,$items,$globalcontext,$localcontext) };
			if(!$@ && defined($result)) {
			my $timestamp = undef;
				if(defined($localcontext->{'timestamp'})) {
					$timestamp = $localcontext->{'timestamp'};
				}
				if(!defined($items->{$item}) || !defined($timestamp) || !defined($items->{$item}->{'timestamp'}) || $items->{$item}->{'timestamp'}<=$timestamp) {
					$self->logHandler->debug("Storing parsed result for $item\n");
					$items->{$item} = $result;
				}else {
					$self->logHandler->debug("Skipping $item, newer entry already loaded\n");
				}
			}else {
				$self->logHandler->debug("Skipping $item: $@\n");
				$errorMsg = "$@";
			}

			# Release content
			undef $itemData;
			undef $content;
		}
	}else {
		$errorMsg = "Incorrect information in data";
		$self->logHandler->warn("Unable to to read configuration\n");
	}
	return $errorMsg;
}

sub getTemplate {
	my $self = shift;
	if(!defined($self->templateHandler)) {
		$self->templateHandler(Template->new({
	
	                COMPILE_DIR => catdir( $serverPrefs->get('cachedir'), 'templates' ),
	                FILTERS => {
	                        'string'        => \&Slim::Utils::Strings::string,
	                        'getstring'     => \&Slim::Utils::Strings::getString,
	                        'resolvestring' => \&Slim::Utils::Strings::resolveString,
	                        'nbsp'          => \&nonBreaking,
	                        'uri'           => \&URI::Escape::uri_escape_utf8,
	                        'unuri'         => \&URI::Escape::uri_unescape,
	                        'utf8decode'    => \&Slim::Utils::Unicode::utf8decode,
	                        'utf8encode'    => \&Slim::Utils::Unicode::utf8encode,
	                        'utf8on'        => \&Slim::Utils::Unicode::utf8on,
	                        'utf8off'       => \&Slim::Utils::Unicode::utf8off,
				'fileurl'       => \&templateFileURLFromPath,
	                },
	
	                EVAL_PERL => 1,
	        }));
	}
	return $self->templateHandler;
}

sub templateFileURLFromPath {
	my $path = shift;
	if($utf8filenames) {
		$path = Slim::Utils::Unicode::utf8off($path);
	}else {
		$path = Slim::Utils::Unicode::utf8on($path);
	}
	$path = decode_entities($path);
	if($driver eq 'SQLite') {
		$path =~ s/\'\'/\'/g;
	}else {
		$path =~ s/\\\"/\"/g;
		$path =~ s/\\\'/\'/g;
		$path =~ s/\\\\/\\/g;
	}
	$path = Slim::Utils::Misc::fileURLFromPath($path);
	$path = Slim::Utils::Unicode::utf8on($path);
	if($driver eq 'SQLite') {
		$path =~ s/%/\\%/g;
		$path =~ s/\'/\'\'/g;
	}else {
		$path =~ s/\\/\\\\/g;
		$path =~ s/%/\\%/g;
		$path =~ s/\"/\\\"/g;
		$path =~ s/\'/\\\'/g;
	}
	$path = encode_entities($path,"&<>\'\"");
	return $path;
}

sub fillTemplate {
	my $self = shift;
	my $filename = shift;
	my $params = shift;

	
	my $output = '';
	$params->{'LOCALE'} = 'utf-8';
	my $template = $self->getTemplate();
	if(!$template->process($filename,$params,\$output)) {
		$self->logHandler->warn("ERROR parsing template: ".$template->error()."\n");
	}
	return $output;
}

sub isEnabled {
	my $self = shift;
	my $client = shift;
	my $xml = shift;

	my $include = 1;
	if(defined($xml->{'minslimserverversion'})) {
		if($::VERSION lt $xml->{'minslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'maxslimserverversion'})) {
		if($::VERSION gt $xml->{'maxslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'requireplugins'}) && $include) {
		$include = 0;
		if(!defined($xml->{'requireplugins'}) || isPluginsInstalled($client,$xml->{'requireplugins'})) {
			$include = 1;
		}
	}
	if($include && defined($xml->{'minpluginversion'}) && $xml->{'minpluginversion'} =~ /(\d+)\.(\d+).*/) {
		my $downloadMajor = $1;
		my $downloadMinor = $2;
		if($self->pluginVersion =~ /(\d+)\.(\d+).*/) {
			my $pluginMajor = $1;
			my $pluginMinor = $2;
			if($pluginMajor==$downloadMajor && $pluginMinor>=$downloadMinor) {
				$include = 1;
			}else {
				$include = 0;
			}
		}
	}	
	if(defined($xml->{'database'}) && $include) {
		$include = 0;
		if($driver eq $xml->{'database'}) {
			$include = 1;
		}
	}
	return $include;
}

sub isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			$enabledPlugin = grep(/$plugin/, Slim::Utils::PluginManager->enabledPlugins($client));
		}
	}
	return $enabledPlugin;
}
sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

# Overridable functions
sub loadTemplate {
	my $self = shift;
	my $client = shift;
	my $template = shift;
	my $parameters = shift;

	return undef;
};

sub parseContentImplementation {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	my $timestamp = undef;
	if(defined($localcontext->{'timestamp'})) {
		$timestamp = $localcontext->{'timestamp'};
	}
	my $cacheName = $item;
	if(defined($localcontext->{'cacheNamePrefix'})) {
		$cacheName = $localcontext->{'cacheNamePrefix'}.$cacheName;
	}

	my $xml = undef;
	if(defined($timestamp) && defined($self->cacheItems) && defined($self->cacheItems->{'items'}->{'content_'.$cacheName}) && $self->cacheItems->{'items'}->{'content_'.$cacheName}->{'timestamp'}>=$timestamp) {
		$xml = $self->cacheItems->{'items'}->{'content_'.$cacheName}->{'data'};
	}else {
		$xml = eval { 	XMLin($content, forcearray => ["item"], keyattr => []) };
	}
	#$self->logHandler->debug(Dumper($xml));
	if ($@) {
		$self->logHandler->warn("Failed to parse configuration ($item) because:\n$@\n");
	}else {
		if(defined($timestamp) && defined($self->cacheItems)) {
			my %entry = (
				'data' => $xml,
				'timestamp' => $timestamp,
			);
			delete $self->cacheItems->{'items'}->{'content_'.$cacheName};
			$self->cacheItems->{'items'}->{'content_'.$cacheName} = \%entry;
		}
		my $include = $self->isEnabled($client,$xml);
		if(defined($xml->{$self->contentType})) {
			$xml->{$self->contentType}->{'id'} = escape($item);
			if(defined($timestamp)) {
				$xml->{$self->contentType}->{'timestamp'} = $timestamp;
			}
		}
		if($include) {
			if($self->checkContent($xml,$globalcontext,$localcontext)) {
		                return $xml->{$self->contentType};
			}else {
				$self->logHandler->debug("Skipping ".$self->contentType." $item\n");
			}
		}
	}
	return undef;
}

sub addStandardParameters {
	my $params = shift;

	$params->{'SqueezeCenterVersion'} = $::VERSION;
	if($driver eq 'mysql') {
		$params->{'MySQL'} = 1;
		$params->{'RANDOMFUNCTION'} = "rand()";
	}else {
		$params->{'SQLite'} = 1;
		$params->{'RANDOMFUNCTION'} = "random()";
	}
}

sub checkContent {
	my $self = shift;
	my $xml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	return 1;
}

sub checkTemplateValues {
	my $self = shift;
	my $template = shift;
	my $valuesXml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;
	
	return 1;
}

sub checkTemplateParameters {
	my $self = shift;
	my $template = shift;
	my $parameters = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	return 1;
}
# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}
1;

__END__
