# 			ConfigManager::WebAdminMethods module
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

package Plugins::SQLPlayList::ConfigManager::WebAdminMethods;

use strict;
use base 'Class::Data::Accessor';

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use POSIX qw(ceil);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use Data::Dumper;
use DBI qw(:sql_types);
use FindBin qw($Bin);
use HTML::Entities;
use Scalar::Util qw(blessed);
use Data::Dumper;

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback pluginId pluginVersion downloadApplicationId extension simpleExtension contentPluginHandler templatePluginHandler contentDirectoryHandler contentTemplateDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler parameterHandler contentParser templateDirectories itemDirectories customTemplateDirectory customItemDirectory supportDownload supportDownloadError webCallbacks webTemplates downloadUrl template templateExtension templateDataExtension) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'downloadApplicationId' => $parameters->{'downloadApplicationId'},
		'extension' => $parameters->{'extension'},
		'simpleExtension' => $parameters->{'simpleExtension'},
		'contentPluginHandler' => $parameters->{'contentPluginHandler'},
		'templatePluginHandler' => $parameters->{'templatePluginHandler'},
		'contentDirectoryHandler' => $parameters->{'contentDirectoryHandler'},
		'contentTemplateDirectoryHandler' => $parameters->{'contentTemplateDirectoryHandler'},
		'templateDirectoryHandler' => $parameters->{'templateDirectoryHandler'},
		'templateDataDirectoryHandler' => $parameters->{'templateDataDirectoryHandler'},
		'parameterHandler' => $parameters->{'parameterHandler'},
		'contentParser' => $parameters->{'contentParser'},
		'templateDirectories' => $parameters->{'templateDirectories'},
		'itemDirectories' => $parameters->{'itemDirectories'},
		'customTemplateDirectory' => $parameters->{'customTemplateDirectory'},
		'customItemDirectory' => $parameters->{'customItemDirectory'},
		'supportDownload' => $parameters->{'supportDownload'},
		'supportDownloadError' => $parameters->{'supportDownloadError'},
		'webCallbacks' => $parameters->{'webCallbacks'},
		'webTemplates' => $parameters->{'webTemplates'},
		'downloadUrl' => $parameters->{'downloadUrl'}
	};

	$self->{'template'} = undef;
	$self->{'templateExtension'} = $parameters->{'templateDirectoryHandler'}->extension;
	$self->{'templateDataExtension'} = $parameters->{'templateDataDirectoryHandler'}->extension;
	bless $self,$class;
	return $self;
}


sub webEditItems {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $items = shift;

        $params->{'pluginWebAdminMethodsItems'} = $items;
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}

	if($self->supportDownload) {
		$params->{'pluginWebAdminMethodsDownloadMessage'} = $self->supportDownloadError;
		$params->{'pluginWebAdminMethodsDownloadSupported'} = 1;
	}else {
		$params->{'pluginWebAdminMethodsDownloadSupported'} = 0;
	}
        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItems'}, $params);
}

sub webEditItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $itemId = shift;
	my $itemHash = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	if(defined($itemId) && defined($itemHash->{$itemId})) {
		if(!defined($itemHash->{$itemId}->{'simple'})) {
			my $data = $self->contentPluginHandler->readDataFromPlugin($client,$itemHash->{$itemId});
			if(!defined($data)) {
				$data = $self->loadItemDataFromAnyDir($itemId);
			}

			if($data) {
				$data = encode_entities($data);
			}
		        $params->{'pluginWebAdminMethodsEditItemData'} = $data;
			$params->{'pluginWebAdminMethodsEditItemFile'} = $itemId.".".$self->extension;
			$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemId.".".$self->extension);

			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItem'}, $params);
		}else {
			my $templateData = $self->loadTemplateValues($client,$itemId,$itemHash->{$itemId});

			if(defined($templateData)) {
				my $template = $templates->{lc($templateData->{'id'})};
				if(defined($template)) {
					my %currentParameterValues = ();
					my $templateDataParameters = $templateData->{'parameter'};
					for my $p (@$templateDataParameters) {
						my $values = $p->{'value'};
						my %valuesHash = ();
						for my $v (@$values) {
							if(ref($v) ne 'HASH') {
								$valuesHash{$v} = $v;
							}
						}
						if(!%valuesHash) {
							$valuesHash{''} = '';
						}
						$currentParameterValues{$p->{'id'}} = \%valuesHash;
					}
					if(defined($template->{'parameter'})) {
						my $parameters = $template->{'parameter'};
						if(ref($parameters) ne 'ARRAY') {
							my @parameterArray = ();
							if(defined($parameters)) {
								push @parameterArray,$parameters;
							}
							$parameters = \@parameterArray;
						}
						my @parametersToSelect = ();
						for my $p (@$parameters) {
							if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
								my $useParameter = 1;
								if(defined($p->{'requireplugins'})) {
									$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
								}
								if($useParameter) {
									$self->parameterHandler->addValuesToTemplateParameter($p,$currentParameterValues{$p->{'id'}});
									push @parametersToSelect,$p;
								}
							}
						}
						$params->{'pluginWebAdminMethodsEditItemParameters'} = \@parametersToSelect;
					}
					$params->{'pluginWebAdminMethodsEditItemTemplate'} = lc($templateData->{'id'});
					$params->{'pluginWebAdminMethodsEditItemFile'} = $itemId.".".$self->simpleExtension;
					$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemId.".".$self->simpleExtension);
					return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditSimpleItem'}, $params);
				}
			}
		}
	}
	return $self->webCallbacks->webEditItems($client,$params);
}

sub webDeleteItemType {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $templateDir = $self->customTemplateDirectory;
	if (defined $templateDir && -d $templateDir) {
		my $templateId = $templateId;
		my $path = catfile($templateDir, $templateId);
		if(-e $path) {
			$self->debugCallback->("Deleting: ".$path."\n");
			unlink($path) or do {
				warn "Unable to delete file: ".$path.": $! \n";
			}
		}
		my $regex1 = "\\.".$self->templateExtension."\$";
		my $regex2 = ".".$self->templateDataExtension;
		$templateId =~ s/$regex1/$regex2/;
		$path = catfile($templateDir, $templateId);
		if(-e $path) {
			$self->debugCallback->("Deleting: ".$path."\n");
			unlink($path) or do {
				warn "Unable to delete file: ".$path.": $! \n";
			}
		}
	}
	$self->changedTemplateConfiguration($client,$params);
	return $self->webCallbacks->webNewItemTypes($client,$params);
}

sub webNewItemTypes {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my @collections = ();
	my $structuredTemplates = $self->structureItemTypes($templates);

	for my $key (sort keys %$structuredTemplates) {
		my $name = $key;
		if($name eq 'AAA') {
			$name = 'Builtin items';
		}elsif($name eq 'ZZZ') {
			$name = 'Custom or downloaded items';
		}elsif($name =~ /^ZZZ(.+)$/) {
			$name = $1;
		}else {
			$name =~ s/^Plugins:://;
			$name =~ s/::Plugin$//;
			$name .= ' items';
		}
		my %collection = (
			'name' => $name,
			'templates' => $structuredTemplates->{$key}
		);
		push @collections,\%collection;
	}

	if($self->supportDownload) {
		$params->{'pluginWebAdminMethodsDownloadMessage'} = $self->supportDownloadError;
		$params->{'pluginWebAdminMethodsDownloadSupported'} = 1;
	}else {
		$params->{'pluginWebAdminMethodsDownloadSupported'} = 0;
	}

	$params->{'pluginWebAdminMethodsTemplates'} = \@collections;
	$params->{'pluginWebAdminMethodsPostUrl'} = $self->webTemplates->{'webNewItemParameters'};
	
	return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItemTypes'}, $params);
}

sub webNewItemParameters {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsNewItemTemplate'} = $templateId;
	my $template = $templates->{$templateId};
	if(defined($template->{'parameter'})) {
		my $parameters = $template->{'parameter'};
		if(ref($parameters) ne 'ARRAY') {
			my @parameterArray = ();
			if(defined($parameters)) {
				push @parameterArray,$parameters;
			}
			$parameters = \@parameterArray;
		}
		my @parametersToSelect = ();
		for my $p (@$parameters) {
			if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
				my $useParameter = 1;
				if(defined($p->{'requireplugins'})) {
					$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
				}
				if($useParameter) {
					$self->parameterHandler->addValuesToTemplateParameter($p);
					push @parametersToSelect,$p;
				}
			}
		}
		$params->{'pluginWebAdminMethodsNewItemParameters'} = \@parametersToSelect;
	}
	return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItemParameters'}, $params);
}

sub webPublishLogin {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $itemId = shift;

	my $username = Slim::Utils::Prefs::set("plugin_".lc($self->pluginId)."_login_user");
	my $password = Slim::Utils::Prefs::set("plugin_".lc($self->pluginId)."_login_password");

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsLoginItem'} = $itemId;
	$params->{'pluginWebAdminMethodsLoginUser'} = $username;
	$params->{'pluginWebAdminMethodsLoginPassword'} = $password;
	
	if(defined($username)) {
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishLogin'}, $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishRegister'}, $params);
	}
}

sub webPublishItemParameters {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $itemId = shift;
	my $itemName = shift;
	my $items = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}

	if($params->{'anonymous'}) {
		$params->{'username'} = undef;
		$params->{'password'} = undef;
	}
	$params->{'pluginWebAdminMethodsLoginItem'} = $itemId;
	$params->{'pluginWebAdminMethodsLoginUser'} = $params->{'username'};
	$params->{'pluginWebAdminMethodsLoginPassword'} = $params->{'password'};
	$params->{'pluginWebAdminMethodsLoginFirstName'} = $params->{'firstname'};
	$params->{'pluginWebAdminMethodsLoginLastName'} = $params->{'lastname'};
	$params->{'pluginWebAdminMethodsLoginEMail'} = $params->{'email'};

	my $versionError = $self->checkWebServiceVersion();
	if(defined($versionError)) {
		$params->{'pluginWebAdminMethodsError'} = $versionError;
		if($params->{'register'}) {
			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishRegister'}, $params);
		}else {
			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishLogin'}, $params);
		}
	}

	if($params->{'register'}) {
		if(!$params->{'username'} || !$params->{'password'} || !$params->{'firstname'} || !$params->{'lastname'}) {
			$params->{'pluginWebAdminMethodsError'} = "Please provide all information";
			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishRegister'}, $params);
		}
		my $email = $params->{'email'};
		if(!defined($email)) {
			$email = '';
		}
		my $answer= eval { SOAP::Lite->uri('http://erland.homeip.net/datacollection')->proxy($self->downloadUrl)->registerUser($params->{'username'},$params->{'password'},$params->{'firstname'},$params->{'lastname'},$email); };
		unless (!defined($answer) || $answer->fault) {
			Slim::Utils::Prefs::set("plugin_".lc($self->pluginId)."_login_user",$params->{'username'});
			Slim::Utils::Prefs::set("plugin_".lc($self->pluginId)."_login_password",$params->{'password'});
		}else {
			if(defined($answer)) {
				$params->{'pluginWebAdminMethodsError'} = niceFault($answer->faultstring);
			}else {
				$params->{'pluginWebAdminMethodsError'} = "Unable to reach publish site";
			}
			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishRegister'}, $params);
		}
	}elsif(!$params->{'anonymous'}){
		my $answer= eval {SOAP::Lite->uri('http://erland.homeip.net/datacollection')->proxy($self->downloadUrl)->loginUser($params->{'username'},$params->{'password'});};
		unless (!defined($answer) || $answer->fault) {
			Slim::Utils::Prefs::set("plugin_".lc($self->pluginId)."_login_user",$params->{'username'});
			Slim::Utils::Prefs::set("plugin_".lc($self->pluginId)."_login_password",$params->{'password'});
		}else {
			if(defined($answer)) {
				$params->{'pluginWebAdminMethodsError'} = niceFault($answer->faultstring);
			}else {
				$params->{'pluginWebAdminMethodsError'} = "Unable to reach publish site";
			}
			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishLogin'}, $params);
		}
	}

	if(defined($itemId) && defined($items->{$itemId})) {
		if(defined($items->{$itemId}->{'simple'})) {
			my $templateData = $self->loadTemplateValues($client,$itemId,$items->{$itemId});
			$itemId =~ s/^published_//;
			if(defined($templateData)) {
				my $template = $templates->{lc($templateData->{'id'})};
				if(defined($template)) {
					$params->{'pluginWebAdminMethodsPublishName'} = $itemName;
					$params->{'pluginWebAdminMethodsPublishDescription'} = $template->{'description'};
					$params->{'pluginWebAdminMethodsPublishUniqueId'} = $itemId;
					if(defined($template->{'downloadidentifier'})) {
						$params->{'pluginWebAdminMethodsPublishOverwrite'} = 1;
					}
					return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishItemParameters'}, $params);
				}
			}
		}else {
			$itemId =~ s/^published_//;
			$params->{'pluginWebAdminMethodsPublishName'} = $itemName;
			$params->{'pluginWebAdminMethodsPublishUniqueId'} = $itemId;
			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishItemParameters'}, $params);
		}
	}
	$params->{'pluginWebAdminMethodsError'} = "Failed to read selected item";
	return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishLogin'}, $params);
}

sub webPublishItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $itemId = shift;
	my $items = shift;
	my $templates = shift;
	my $contentTemplateInsertText = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}

	$params->{'pluginWebAdminMethodsLoginItem'} = $itemId;
	$params->{'pluginWebAdminMethodsLoginUser'} = $params->{'username'};
	$params->{'pluginWebAdminMethodsLoginPassword'} = $params->{'password'};
	$params->{'pluginWebAdminMethodsPublishName'} = $params->{'itemname'};
	$params->{'pluginWebAdminMethodsPublishDescription'} = $params->{'itemdescription'};
	$params->{'pluginWebAdminMethodsPublishUniqueId'} = $params->{'itemuniqueid'};
	$params->{'pluginWebAdminMethodsPublishOverwrite'} = $params->{'overwrite'};
	my $overwriteFlag = 0;
	if($params->{'overwrite'}) {
		$overwriteFlag = 1;
	}

	if(!$params->{'itemname'} || !$params->{'itemdescription'} || !$params->{'itemuniqueid'}) {
		$params->{'pluginWebAdminMethodsError'} = "All parameters must be specified";
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishItemParameters'}, $params);
	}
	if(defined($itemId) && defined($items->{$itemId})) {
		my $publishData = undef;
		if($params->{'itemuniqueid'} !~ /^published_/) {
			$params->{'itemuniqueid'} = 'published_'.$params->{'itemuniqueid'};
		}
		if(defined($items->{$itemId}->{'simple'})) {
			my $templateData = $self->loadTemplateValues($client,$itemId,$items->{$itemId});
			if(defined($templateData)) {
				my $template = $templates->{lc($templateData->{'id'})};
				if(defined($template)) {
					my $templateFile = $template->{'id'};
					if(defined($templateData->{'templatefile'})) {
						$templateFile = $templateData->{'templatefile'};
					}
					my $templateXml = $self->loadTemplateFromAnyDir($template->{'id'});
					$templateXml = $self->updateTemplateBeforePublish($client,$params,$templateXml);

					$publishData = '';
					$publishData .= '<entry>';
					$publishData .= '<id>'.$params->{'itemuniqueid'}.'</id>';
					$publishData .= '<title>'.$params->{'itemname'}.'</title>';
					$publishData .= '<description>'.$params->{'itemdescription'}.'</description>';
					$publishData .= '<data>';
					$publishData .= '<type>xml</type>';
					$publishData .= '<content>'.encode_entities($templateXml,"&<>\'\"").'</content>';
					$publishData .= '</data>';
					$publishData .= '<data>';
					$publishData .= '<type>template</type>';
					$publishData .= '<content>'.encode_entities($self->loadTemplateDataFromAnyDir($templateFile),"&<>\'\"").'</content>';
					$publishData .= '</data>';
					$publishData .= '</entry>';
				}
			}
		}else {
			my $templateXml = '';
			$templateXml .= '<?xml version="1.0" encoding="utf-8"?>'."\n";
			$templateXml .= '<'.lc($self->pluginId).'>'."\n";
			$templateXml .= '	<template>'."\n";
			$templateXml .= '		<name>'.$params->{'itemname'}.'</name>'."\n";
			$templateXml .= '		<description>'.$params->{'itemdescription'}.'</description>'."\n";
			$templateXml .= $self->getTemplateParametersForPublish($client,$params);
			$templateXml .= '	</template>'."\n";
			$templateXml .= '</'.lc($self->pluginId).'>'."\n";
 
                
			my $templateData = $self->contentPluginHandler->readDataFromPlugin($client,$items->{$itemId});
			if(!defined($templateData)) {
				$templateData = $self->loadItemDataFromAnyDir($itemId);
			}
			$templateData = $self->updateContentBeforePublish($client,$params,$templateData);
		
			$publishData = '';
			$publishData .= '<entry>';
			$publishData .= '<id>'.$params->{'itemuniqueid'}.'</id>';
			$publishData .= '<title>'.$params->{'itemname'}.'</title>';
			$publishData .= '<description>'.$params->{'itemdescription'}.'</description>';
			$publishData .= '<data>';
			$publishData .= '<type>xml</type>';
			$publishData .= '<content>'.encode_entities($templateXml,"&<>\'\"").'</content>';
			$publishData .= '</data>';
			$publishData .= '<data>';
			$publishData .= '<type>template</type>';
			$publishData .= '<content>'.encode_entities($templateData,"&<>\'\"").'</content>';
			$publishData .= '</data>';
			$publishData .= '</entry>';
		}
		if(defined($publishData)) {
			my $answer= eval {SOAP::Lite->uri('http://erland.homeip.net/datacollection')->proxy($self->downloadUrl)->addDataEntry($params->{'username'},$params->{'password'},$self->downloadApplicationId,0,$overwriteFlag, $publishData);};
			unless (!defined($answer) || $answer->fault) {
				return $self->webCallbacks->webEditItems($client,$params);
			}else {
				if(defined($answer)) {
					$params->{'pluginWebAdminMethodsError'} = niceFault($answer->faultstring);
				}else {
					$params->{'pluginWebAdminMethodsError'} = "Unable to reach publish site";
				}
				return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishItemParameters'}, $params);
			}
		}
	}
	$params->{'pluginWebAdminMethodsError'} = "Failed to read selected item";
	return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webPublishItemParameters'}, $params);
}

sub webDownloadItems {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	
	my $versionError = $self->checkWebServiceVersion();
	if(defined($versionError)) {
		$params->{'pluginWebAdminMethodsError'} = $versionError;
		return $self->webCallbacks->webNewItemTypes($client,$params);
	}
	my $answer= eval {SOAP::Lite->uri('http://erland.homeip.net/datacollection')->proxy($self->downloadUrl)->getEntries($self->downloadApplicationId);};
	unless (!defined($answer) || $answer->fault) {
		my $result = $answer->result();
		my $xml = eval { XMLin($result, forcearray => ['collection','entry'], keyattr => []) };
		my $collections = $xml->{'collection'};
		if(defined($collections)) {
			my @collectionTemplates = ();
			for my $collection (@$collections) {
				my %collectionTemplate = (
					'id' => $collection->{'id'},
					'name' => $collection->{'title'},
					'user' => $collection->{'username'}
				);
				if(defined($collection->{'description'}) && ref($collection->{'description'}) ne 'HASH') {
					$collectionTemplate{'description'} = $collection->{'description'};
				}else {
					$collectionTemplate{'description'} = '';
				}
				if($collectionTemplate{'user'} eq $self->pluginId) {
					$collectionTemplate{'user'} = 'anonymous';
				}
				if($collectionTemplate{'name'} eq $self->pluginId) {
					$collectionTemplate{'name'} = 'Downloadable items';
				}
				if($collectionTemplate{'description'} eq 'Collection for '.$self->pluginId) {
					$collectionTemplate{'description'} = '';
				}

				my $entries = $collection->{'entries'}->{'entry'};
				if(defined($entries)) {
					my @entryTemplates = ();
					for my $entry (@$entries) {
						my %template = (
							'id' => $entry->{'id'},
							'name' => $entry->{'title'},
							'description' => $entry->{'description'},
							'lastchanged' => $entry->{'lastchanged'}
						);
						push @entryTemplates, \%template;
					}
					if(scalar(@entryTemplates>0)) {
						$collectionTemplate{'templates'} = \@entryTemplates;
					}
				}
				if(defined($collectionTemplate{'templates'})) {
					push @collectionTemplates, \%collectionTemplate;
				}
			}
			$params->{'pluginWebAdminMethodsTemplates'} = \@collectionTemplates;
			$params->{'pluginWebAdminMethodsPostUrl'} = $self->webTemplates->{'webDownloadItem'};
			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItemTypes'}, $params);
		}
		$params->{'pluginWebAdminMethodsError'} = "No items available to download";
		$self->changedTemplateConfiguration($client,$params);
		return $self->webCallbacks->webNewItemTypes($client,$params);
	}else {
		if(defined($answer)) {
			$params->{'pluginWebAdminMethodsError'} = "Unable to reach download site: ".niceFault($answer->faultstring);
		}else {
			$params->{'pluginWebAdminMethodsError'} = "Unable to reach download site";
		}
		return $self->webCallbacks->webNewItemTypes($client,$params);
	}
}

sub webDownloadNewItems {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}

	my $error = '';
	my $message = '';
	for my $key (sort keys %$templates) {
		my $template = $templates->{$key};
		if(defined($template->{'downloadidentifier'})) {
			my $identifier = $key;
			my $regex1 = "\\.".$self->templateExtension."\$";
			$identifier =~ s/$regex1//;
			if(defined($template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType})) {
				$identifier = undef;
			}
			my $result = $self->downloadItem($template->{'downloadidentifier'},$identifier,1,1);
			if(defined($result->{'error'})) {
				$error .= $template->{'name'}."(".$template->{'id'}.") : ".$result->{'error'}."<br>";
			}else {
				$message .= "- ".$template->{'name'}." (".$key.")<br>";
			}
		}
	}
	if($message ne '') {
		$params->{'pluginWebAdminMethodsMessage'} = "Downloaded following:<br>".$message;
	}
	if($error ne '') {
		$params->{'pluginWebAdminMethodsError'} = $error;
	}
	$self->changedTemplateConfiguration($client,$params);
	return $self->webCallbacks->webEditItems($client,$params);
}

sub webDownloadItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $result = $self->downloadItem($templateId,$params->{'customname'},$params->{'overwrite'});
	if(defined($result->{'error'})) {
		$params->{'pluginWebAdminMethodsError'} = $result->{'error'};
		return $self->webCallbacks->webDownloadItems($client,$params);
	}
	if($result->{'filenamecollision'}) {
		$params->{'pluginWebAdminMethodsTemplate'} = $templateId;
		$params->{'pluginWebAdminMethodsUniqueId'} = $result->{'template'};
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webSaveDownloadedItem'}, $params);
	}else {
		$params->{'itemtemplate'} = $result->{'template'};
		$self->changedTemplateConfiguration($client,$params);
		return $self->webCallbacks->webNewItemParameters($client,$params);
	}
}

sub webNewItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $templateFile = $templateId;
	my $itemFile = $templateFile;
	my $regex1 = "\\.".$self->templateExtension."\$";
	my $regex2 = ".".$self->templateDataExtension;
	$templateFile =~ s/$regex1/$regex2/;
	$itemFile =~ s/$regex1//;

	my $template = $templates->{$templateId};
	my $menytype = $params->{'itemtype'};

	if(-e catfile($self->customItemDirectory,unescape($itemFile).".".$self->extension) || -e catfile($self->customItemDirectory,unescape($itemFile).".".$self->simpleExtension)) {
		my $i=1;
		while(-e catfile($self->customItemDirectory,unescape($itemFile).$i.".".$self->extension) || -e catfile($self->customItemDirectory,unescape($itemFile).$i.".".$self->simpleExtension)) {
			$i = $i + 1;
		}
		$itemFile .= $i;
	}
	if($menytype eq 'advanced') {
		$itemFile .= ".".$self->extension;
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						$self->parameterHandler->addValuesToTemplateParameter($p);
						my $value = $self->parameterHandler->getValueOfTemplateParameter($params,$p);
						$templateParameters{$p->{'id'}} = $value;
					}
				}
			}
		}
		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType})) {
			my $pluginTemplate = $template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = \$self->templatePluginHandler->readDataFromPlugin($client,$template,\%templateParameters);
		}else {
			$templateFileData = $templateFile;
		}
		my $itemData = undef;
		if($doParsing) {
			$itemData = $self->fillTemplate($templateFileData,\%templateParameters);
		}else {
			$itemData = $templateFileData;
		}
		$itemData = Slim::Utils::Unicode::utf8on($itemData);
		$itemData = Slim::Utils::Unicode::utf8encode_locale($itemData);
		$itemData = encode_entities($itemData,"&<>\'\"");
		if(length($itemData)>10000) {
			$self->debugCallback->("Warning! Large configuration, ".length($itemData)." characters\n");
		        $params->{'pluginWebAdminMethodsEditItemSizeWarning'} = "This configuration is very large, due to size limitations it might fail when you try to save it<br>Temporary solution: If save fails, click back in web browser and copy the information in the configuration field to a text file and save it to the ".$self->customItemDirectory." directory with a filename with extension .".$self->extension;
		}
        	$params->{'pluginWebAdminMethodsEditItemData'} = $itemData;
		$params->{'pluginWebAdminMethodsEditItemFile'} = $itemFile;
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemFile);
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItem'}, $params);
	}else {
		$itemFile .= ".".$self->simpleExtension;
		my %templateParameters = ();
		for my $p (keys %$params) {
			my $regexp = '^'.$self->parameterHandler->parameterPrefix.'_';
			if($p =~ /$regexp/) {
				$templateParameters{$p}=$params->{$p};
			}
		}
		$params->{'pluginWebAdminMethodsEditItemParameters'} = \%templateParameters;
		$params->{'pluginWebAdminMethodsNewItemTemplate'} = $templateId;
		$params->{'pluginWebAdminMethodsEditItemFile'} = $itemFile;
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemFile);
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewSimpleItem'}, $params);
	}
}

sub webSaveSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $templateFile = $templateId;
	my $regex1 = "\\.".$self->templateExtension."\$";
	my $regex2 = ".".$self->templateDataExtension;
	$templateFile =~ s/$regex1/$regex2/;

	my $regex3 = "\\.".$self->simpleExtension."\$";
	my $itemFile = $params->{'file'};
	$itemFile =~ s/$regex3//;

	my $template = $templates->{$templateId};
	my $itemtype = $params->{'itemtype'};

	if($itemtype eq 'advanced') {
		$itemFile .= ".".$self->extension;
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			if(ref($parameters) ne 'ARRAY') {
				my @parameterArray = ();
				if(defined($parameters)) {
					push @parameterArray,$parameters;
				}
				$parameters = \@parameterArray;
			}
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						$self->parameterHandler->addValuesToTemplateParameter($p);
						my $value = $self->parameterHandler->getValueOfTemplateParameter($params,$p);
						$templateParameters{$p->{'id'}} = $value;
					}
				}
			}
		}
		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType})) {
			my $pluginTemplate = $template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = \$self->templatePluginHandler->readDataFromPlugin($client,$template,\%templateParameters);
		}else {
			$templateFileData = $templateFile;
		}
		my $itemData = undef;
		if($doParsing) {
			$itemData = $self->fillTemplate($templateFileData,\%templateParameters);
		}else {
			$itemData = $templateFileData;
		}
		$itemData = Slim::Utils::Unicode::utf8on($itemData);
		$itemData = Slim::Utils::Unicode::utf8encode_locale($itemData);
		$itemData = encode_entities($itemData,"&<>\'\"");
		if(length($itemData)>10000) {
			$self->debugCallback->("Warning! Large configuration, ".length($itemData)." characters\n");
		        $params->{'pluginWebAdminMethodsEditItemSizeWarning'} = "This configuration is very large, due to size limitations it might fail when you try to save it<br>Temporary solution: If save fails, click back in web browser and copy the information in the configuration field to a text file and save it to the ".$self->customItemDirectory." directory with a filename with extension .".$self->extension;
		}
        	$params->{'pluginWebAdminMethodsEditItemData'} = $itemData;
		$params->{'pluginWebAdminMethodsEditItemDeleteSimple'} = $params->{'file'};
		$params->{'pluginWebAdminMethodsEditItemFile'} = $itemFile;
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemFile);
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItem'}, $params);
	}else {
		$params->{'pluginWebAdminMethodsError'} = undef;
	
		if (!$params->{'file'}) {
			$params->{'pluginWebAdminMethodsError'} = 'Filename is mandatory';
		}
	
		my $dir = $self->customItemDirectory;
		
		if (!defined $dir || !-d $dir) {
			$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
		}
		my $file = unescape($params->{'file'});
		my $url = catfile($dir, $file);
		
		my $error = $self->checkSaveSimpleItem($client,$params);
		if(defined($error)) {
			$params->{'pluginWebAdminMethodsError'} = $error;
		}
		if(!$self->saveSimpleItem($client,$params,$url,$templateId,$templates)) {
		        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditSimpleItem'}, $params);
		}else {
			$self->changedItemConfiguration($client,$params);
			return $self->webCallbacks->webEditItems($client,$params);
		}
	}
}

sub webDeleteItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $itemId = shift;
	my $items = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $dir = $self->customItemDirectory;
	my $file = unescape($itemId);
	if(defined($items->{$itemId}->{'simple'})) {
		$file .= ".".$self->simpleExtension;
	}else {
		$file .= ".".$self->extension;
	}
	my $url = catfile($dir, $file);
	if(defined($dir) && -d $dir && $file && -e $url) {
		unlink($url) or do {
			warn "Unable to delete file: ".$url.": $! \n";
		}
	}		
	$self->changedItemConfiguration($client,$params);
	return $self->webCallbacks->webEditItems($client,$params);
}

sub webSaveNewSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsError'} = undef;

	if (!$params->{'file'}) {
		$params->{'pluginWebAdminMethodsError'} = 'All fields are mandatory';
	}

	my $dir = $self->customItemDirectory;
	
	if (!defined $dir || !-d $dir) {
		$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
	}
	my $file = unescape($params->{'file'});
	my $customFile = $file;
	my $regexp1 = ".".$self->simpleExtension."\$";
	$regexp1 =~ s/\./\\./;
	my $regexp2 = ".".$self->extension;
	$customFile =~ s/$regexp1/$regexp2/;
	my $url = catfile($dir, $file);
	my $customUrl = catfile($dir, $customFile);

	if(!defined($params->{'pluginWebAdminMethodsError'}) && -e $url && !$params->{'overwrite'}) {
		$params->{'pluginWebAdminMethodsError'} = 'Invalid filename, file already exist';
	}
	if(!defined($params->{'pluginWebAdminMethodsError'}) && -e $customUrl && !$params->{'overwrite'}) {
		$params->{'pluginWebAdminMethodsError'} = 'Invalid filename, customized item with this name already exist';
	}

	my $error = $self->checkSaveSimpleItem($client,$params);
	if(defined($error)) {
		$params->{'pluginWebAdminMethodsError'} = $error;
	}
	if(!$self->saveSimpleItem($client,$params,$url,$templateId,$templates)) {
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewSimpleItem'}, $params);
	}else {
		if($params->{'overwrite'}) {
			if(-e $customUrl) {
				$self->debugCallback->("Deleting $url\n");
				unlink($customUrl) or do {
					warn "Unable to delete file: ".$customUrl.": $! \n";
				}
			}
		}
		$self->changedItemConfiguration($client,$params);
		return $self->webCallbacks->webEditItems($client,$params);
	}
}

sub webSaveNewItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsError'} = undef;

	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginWebAdminMethodsError'} = 'All fields are mandatory';
	}

	my $dir = $self->customItemDirectory;
	
	if (!defined $dir || !-d $dir) {
		$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($dir, $file);
	
	if(!defined($params->{'pluginWebAdminMethodsError'}) && -e $url) {
		$params->{'pluginWebAdminMethodsError'} = 'Invalid filename, file already exist';
	}

	if(!$self->saveItem($client,$params,$url)) {
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItem'}, $params);
	}else {
		$self->changedItemConfiguration($client,$params);
		return $self->webCallbacks->webEditItems($client,$params);
	}
}

sub webSaveItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsError'} = undef;

	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginWebAdminMethodsError'} = 'All fields are mandatory';
	}

	my $dir = $self->customItemDirectory;
	
	if (!defined $dir || !-d $dir) {
		$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($dir, $file);
	
	if(!$self->saveItem($client,$params,$url)) {
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItem'}, $params);
	}else {
		if(defined($params->{'deletesimple'})) {
			my $file = unescape($params->{'deletesimple'});
			my $url = catfile($dir, $file);
			if(-e $url) {
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}
		$self->changedItemConfiguration($client,$params);
		return $self->webCallbacks->webEditItems($client,$params);
	}
}

sub changedItemConfiguration {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	$self->webCallbacks->changedItemConfiguration($client,$params);
}

sub changedTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	$self->webCallbacks->changedTemplateConfiguration($client,$params);
}

sub checkSaveItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	return undef;
}

sub checkSaveSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	return undef;
}

sub saveItem 
{
	my ($self, $client, $params, $url) = @_;
	my $fh;

	my $regexp = ".".$self->extension."\$";
	$regexp =~ s/\./\\./;
	if(!($url =~ /$regexp/)) {
		$params->{'pluginWebAdminMethodsError'} = 'Filename must end with .'.$self->extension;
	}
	if(!($params->{'pluginWebAdminMethodsError'}) && defined($self->contentParser)) {
		my %items = ();
		my %globalcontext = (
			'source' => 'custom'
		);
		my $error =  $self->contentParser->parse($client,'test',$params->{'text'},\%items,\%globalcontext);

		if($error) {
			$params->{'pluginWebAdminMethodsError'} = "Reading configuration: <br>".$error;
		}else {
			my $errorMsg = $self->checkSaveItem($client,$params,$items{'test'});
			if(defined($errorMsg)) {
				$params->{'pluginWebAdminMethodsError'} = $errorMsg;
			}
		}
	}

	if(!($params->{'pluginWebAdminMethodsError'})) {
		$self->debugCallback->("Opening configuration file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginWebAdminMethodsError'} = 'Error saving';
		};
	}
	if(!($params->{'pluginWebAdminMethodsError'})) {

		$self->debugCallback->("Writing to file: $url\n");
		print $fh $params->{'text'};
		$self->debugCallback->("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginWebAdminMethodsError'}) {
		$params->{'pluginWebAdminMethodsEditItemFile'} = $params->{'file'};
		$params->{'pluginWebAdminMethodsEditItemData'} = encode_entities($params->{'text'});
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($params->{'pluginWebAdminMethodsEditItemFile'});
		return undef;
	}else {
		return 1;
	}
}

sub saveSimpleItem {
	my ($self, $client, $params, $url,$templateId,$templates) = @_;
	my $fh;

	my $regexp = $self->simpleExtension;
	$regexp =~ s/\./\\./;
	$regexp = ".*".$regexp."\$";
	if(!($url =~ /$regexp/)) {
		$params->{'pluginWebAdminMethodsError'} = "Filename must end with .$self->simpleExtension";
	}

	if(!($params->{'pluginWebAdminMethodsError'})) {
		$self->debugCallback->("Opening configuration file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginWebAdminMethodsError'} = 'Error saving';
		};
	}
	if(!($params->{'pluginWebAdminMethodsError'})) {
		my $template = $templates->{$templateId};
		my %templateParameters = ();
		my $data = "";
		$data .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<".lc($self->pluginId).">\n\t<template>\n\t\t<id>".$templateId."</id>";
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			if(ref($parameters) ne 'ARRAY') {
				my @parameterArray = ();
				if(defined($parameters)) {
					push @parameterArray,$parameters;
				}
				$parameters = \@parameterArray;
			}
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						$self->parameterHandler->addValuesToTemplateParameter($p);
						my $value = $self->parameterHandler->getXMLValueOfTemplateParameter($params,$p);
						if($p->{'quotevalue'}) {
							$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\" quotevalue=\"1\">";
						}else {
							$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\">";
						}
						$data .= $value.'</parameter>';
					}
				}
			}
		}
		$data .= "\n\t</template>\n</".lc($self->pluginId).">\n";
		$self->debugCallback->("Writing to file: $url\n");
		print $fh $data;
		$self->debugCallback->("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginWebAdminMethodsError'}) {
		my $template = $templates->{$templateId};
		if(defined($template->{'parameter'})) {
			my @templateDataParameters = ();
			my $parameters = $template->{'parameter'};
			if(ref($parameters) ne 'ARRAY') {
				my @parameterArray = ();
				if(defined($parameters)) {
					push @parameterArray,$parameters;
				}
				$parameters = \@parameterArray;
			}
			for my $p (@$parameters) {
				$self->parameterHandler->addValuesToTemplateParameter($p);
				my $value = $self->parameterHandler->getXMLValueOfTemplateParameter($params,$p);
				if(defined($value) && $value ne '') {
					my $valueData = '<data>'.$value.'</data>';
					my $xmlValue = eval { XMLin($valueData, forcearray => ['value'], keyattr => []) };
					if(defined($xmlValue)) {
						$xmlValue->{'id'} = $p->{'id'};
						push @templateDataParameters,$xmlValue;
					}
				}
			}			
			my %currentParameterValues = ();
			for my $p (@templateDataParameters) {
				my $values = $p->{'value'};
				my %valuesHash = ();
				for my $v (@$values) {
					if(ref($v) ne 'HASH') {
						$valuesHash{$v} = $v;
					}
				}
				if(!%valuesHash) {
					$valuesHash{''} = '';
				}
				$currentParameterValues{$p->{'id'}} = \%valuesHash;
			}

			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						$self->parameterHandler->setValueOfTemplateParameter($p,$currentParameterValues{$p->{'id'}});
						push @parametersToSelect,$p;
					}
				}
			}
			$params->{'pluginWebAdminMethodsEditItemParameters'} = \@parametersToSelect;
		}
		$params->{'pluginWebAdminMethodsEditItemTemplate'} = $templateId;
		$params->{'pluginWebAdminMethodsEditItemFile'} = $params->{'file'};
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($params->{'pluginWebAdminMethodsEditItemFile'});
		return undef;
	}else {
		return 1;
	}
}

sub downloadItem {
	my $self = shift;
	my $id = shift;
	my $customname = shift;
	my $overwrite = shift;
	my $onlyOverwrite = shift;

	my $answer= eval {SOAP::Lite->uri('http://erland.homeip.net/datacollection')->proxy($self->downloadUrl)->getEntry($id) };
	my %result = ();
	unless (!defined($answer) || $answer->fault) {
		my $result = $answer->result();
		my $xml = eval { XMLin($result, forcearray => ['data'], keyattr => []) };
		my $template = $xml->{'uniqueid'};
		if(!defined($customname)) {
			$customname = $template;
		}elsif($onlyOverwrite && $customname ne $template) {
			$result{'error'} = "Id doesnt match name, must be downloaded manually";
			return \%result;
		}
		my $datas = $xml->{'datas'}->{'data'};
		if(defined($datas)) {
			my %dataToStore = ();
			my $username = $xml->{'collection'}->{'username'};
			if($username eq $self->pluginId) {
				$username = 'anonymous';
			}
			my $title = $xml->{'collection'}->{'title'};
			if($title eq $self->pluginId) {
				$title = 'Downloaded items';
			}
			my $downloadsection = $title." (by ".$username.")";
			my $incompatibleVersions = 0;
			for my $data (@$datas) {
				if($data->{'type'} eq 'template') {
					my $content = $data->{'content'};
					$dataToStore{$data->{'type'}} = $content;
				}elsif($data->{'type'} eq 'xml') {
					my $content = $data->{'content'};
					$content =~ s/\s*<downloadidentifier>.*<\/downloadidentifier>//m;
					$content =~ s/\s*<downloadsection>.*<\/downloadsection>//m;
					$content =~ s/<template>/<template>\n\t\t<downloadsection>$downloadsection<\/downloadsection>\n\t\t<downloadidentifier>$id<\/downloadidentifier>/m;
					if(defined($xml->{'lastchanged'})) {
						$content =~ s/\s*<lastchanged>.*<\/lastchanged>//m;
						my $lastchanged = $xml->{'lastchanged'};
						$content =~ s/<\/downloadidentifier>/<\/downloadidentifier>\n\t\t<lastchanged>$lastchanged<\/lastchanged>/m;
					}
					if($content =~ /<minpluginversion>(\d+)\.(\d+).*<\/minpluginversion>/) {
						my $downloadMajor = $1;
						my $downloadMinor = $2;
						if($self->pluginVersion =~ /(\d+)\.(\d+).*/) {
							my $pluginMajor = $1;
							my $pluginMinor = $2;

							if($pluginMajor>=$downloadMajor && $pluginMinor>=$downloadMinor) {
								$dataToStore{$data->{'type'}} = $content;
							}else {
								$incompatibleVersions = 1;
							}
						}
					}else {
						$dataToStore{$data->{'type'}} = $content;
					}
				}
			}
			if(defined($dataToStore{'template'}) && defined($dataToStore{'xml'})) {
				my $templateDir = $self->customTemplateDirectory;
				for my $key (keys %dataToStore) {
					my $file = $customname;
					if($key eq 'xml') {
						$file .= ".".$self->templateExtension;
					}elsif ($key eq 'template') {
						$file .= ".".$self->templateDataExtension;
					}else {
						$file .= ".".$key;
					}
					my $url = catfile($templateDir,$file);
					if(-e $url && !$overwrite) {
						$result{'filenamecollision'} = 1;
						$result{'template'} = $customname;
						return \%result;
					}
					my $fh;
					open($fh,"> $url") or do {
						$result{'error'} = 'Error saving downloaded item';
					        return \%result;
					};
					$self->debugCallback->("Writing to file: $url\n");
					print $fh $dataToStore{$key};
					$self->debugCallback->("Writing to file succeeded\n");
					close $fh;
				}
				$result{'template'} = $customname.'.'.$self->templateExtension;
				return \%result;
			}elsif($incompatibleVersions) {
				$result{'error'} = "Unable to download, newer plugin version required";
			}else {
				$result{'error'} = "Unable to download";
			}
			return \%result;
		}
		$result{'error'} = "No items available to download";
		return \%result;
	}else {
		$result{'error'} = "Unable to reach download site";
		return \%result;
	}
}

sub updateTemplateBeforePublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateData = shift;

	my $name = $params->{'itemname'};
	my $description = $params->{'itemdescription'};

	$templateData =~ s/<templatefile>.*<\/templatefile>//m;
	if(defined($name)) {
		$templateData =~ s/<name>.*<\/name>/<name>$name<\/name>/m;
	}
	if(defined($description)) {
		$templateData =~ s/<description>.*<\/description>/<description>$description<\/description>/m;
	}
	$templateData =~ s/\s*<downloadidentifier>.*<\/downloadidentifier>//m;
	$templateData =~ s/\s*<downloadsection>.*<\/downloadsection>//m;
	$templateData =~ s/\s*<lastchanged>.*<\/lastchanged>//m;

	return $templateData;
}

sub getTemplateParametersForPublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	return '';
}
sub updateContentBeforePublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $contentData = shift;

	return $contentData;
}

sub structureItemTypes {
	my $self = shift;
	my $templates = shift;
	
	my %templatesHash = ();
	
	for my $key (keys %$templates) {
		my $plugin = $templates->{$key}->{lc($self->templatePluginHandler->pluginId).'_plugin'};
		if(defined($templates->{$key}->{'customtemplate'})) {
			$plugin = 'ZZZ';
			if(defined($templates->{$key}->{'downloadsection'})) {
				$plugin .= $templates->{$key}->{'downloadsection'};
			}
		}
		if(!defined($plugin)) {
			$plugin = 'AAA';
		}
		my $array = $templatesHash{$plugin};
		if(!defined($array)) {
			my @newArray = ();
			$array = \@newArray;
			$templatesHash{$plugin} = $array;
		}
		push @$array,$templates->{$key};
	}
	for my $key (keys %templatesHash) {
		my $array = $templatesHash{$key};
		my @sortedArray = sort { uc($a->{'name'}) cmp uc($b->{'name'}) } @$array;
		$templatesHash{$key} = \@sortedArray;
	}
	return \%templatesHash;
}

sub loadItemDataFromAnyDir {
	my $self = shift;
	my $itemId = shift;
	my $data = undef;

	my $directories = $self->itemDirectories;
	for my $dir (@$directories) {
		$data = $self->contentDirectoryHandler->readDataFromDir($dir,$itemId);
		if(defined($data)) {
			last;
		}
	}
	return $data;
}

sub loadTemplateFromAnyDir {
	my $self = shift;
	my $templateId = shift;
	my $data = undef;

	my $directories = $self->templateDirectories;
	for my $dir (@$directories) {
		$data = $self->templateDirectoryHandler->readDataFromDir($dir,$templateId);
		if(defined($data)) {
			last;
		}
	}
	return $data;
}

sub loadTemplateDataFromAnyDir {
	my $self = shift;
	my $templateId = shift;
	my $data = undef;

	my $directories = $self->templateDirectories;
	for my $dir (@$directories) {
		$data = $self->templateDataDirectoryHandler->readDataFromDir($dir,$templateId);
		if(defined($data)) {
			last;
		}
	}
	return $data;
}

sub loadTemplateValues {
	my $self = shift;
	my $client = shift;
	my $itemId = shift;
	my $item = shift;
	my $templateData = undef;

	#my $itemItem = $items->{$item};
	my $content  = $self->contentPluginHandler->readDataFromPlugin($client,$item);
	if ( $content ) {
		$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
		my $xml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
		#$self->debugCallback->(Dumper($valuesXml));
		if ($@) {
			$self->errorCallback->("Failed to parse configuration because:\n$@\n");
		}else {
			$templateData = $xml->{'template'};
		}
	}

	my $itemDirectories = $self->itemDirectories;
	for my $dir (@$itemDirectories) {
		$content = $self->contentTemplateDirectoryHandler->readDataFromDir($dir,$itemId);
		if(defined($content)) {
			$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
			my $xml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
			#$self->debugCallback->(Dumper($valuesXml));
			if ($@) {
				$self->errorCallback->("Failed to parse configuration because:\n$@\n");
			}else {
				$templateData = $xml->{'template'};
			}
		}
		if(defined($templateData)) {
			last;
		}
	}
	return $templateData;
}

sub isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			$enabledPlugin = Slim::Utils::PluginManager::enabledPlugin($plugin,$client);
		}
	}
	return $enabledPlugin;
}

sub checkWebServiceVersion {
	my $self = shift;
	my $answer = undef;
	eval {
		$answer = SOAP::Lite->uri('http://erland.homeip.net/datacollection')->proxy($self->downloadUrl)->apiVersion();
	};
	if ($@) {
		return "Unable to contact download/publish site";
	}
	unless ($answer->fault) {
		if($answer->result() =~ /^(\d+)\.(\d+)$/) {
			if($1 ne "1") {
				return "This version of ".$self->pluginId." plugin is incompatible with the current download service, please upgrade";
			}else {
				return undef;
			}
		}else {
			return "This version of ".$self->pluginId." plugin is incompatible with the current download service, please upgrade";
		}
	} else {
		return "Unable to contact download/publish site, ".niceFault($answer->faultstring);
	}
}

sub getTemplate {
	my $self = shift;
	if(!defined($self->template)) {
		$self->template(Template->new({
	
	                INCLUDE_PATH => $self->templateDirectories,
	                COMPILE_DIR => catdir( Slim::Utils::Prefs::get('cachedir'), 'templates' ),
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
	                        'fileurl'       => \&fileURLFromPath,
	                },
	
	                EVAL_PERL => 1,
	        }));
	}
	return $self->template;
}

sub fileURLFromPath {
	my $path = shift;
	$path = Slim::Utils::Unicode::utf8off($path);
	$path = Slim::Utils::Misc::fileURLFromPath(decode_entities($path));
	$path =~ s/\\/\\\\/g;
	$path =~ s/%/\\%/g;
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
		$self->errorCallback->("ERROR parsing template: ".$template->error()."\n");
	}
	return $output;
}

sub niceFault {
	my $fault = shift;
	if(defined($fault)) {
		$fault =~ s/^.*?Exception.*?:\s*//;
	}
	return $fault;
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
