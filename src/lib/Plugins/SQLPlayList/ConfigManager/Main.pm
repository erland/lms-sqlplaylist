# 			ConfigManager::Main module
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

package Plugins::SQLPlayList::ConfigManager::Main;

use strict;

use base 'Class::Data::Accessor';

use Slim::Utils::Prefs;
use Plugins::SQLPlayList::ConfigManager::TemplateParser;
use Plugins::SQLPlayList::ConfigManager::ContentParser;
use Plugins::SQLPlayList::ConfigManager::TemplateContentParser;
use Plugins::SQLPlayList::ConfigManager::PluginLoader;
use Plugins::SQLPlayList::ConfigManager::DirectoryLoader;
use Plugins::SQLPlayList::ConfigManager::ParameterHandler;
use Plugins::SQLPlayList::ConfigManager::PlaylistWebAdminMethods;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(logHandler pluginPrefs pluginId downloadApplicationId pluginVersion supportDownloadError contentDirectoryHandler templateContentDirectoryHandler mixDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler contentPluginHandler mixPluginHandler templatePluginHandler parameterHandler templateParser contentParser mixParser templateContentParser webAdminMethods addSqlErrorCallback templates items) );

my $prefs = preferences('plugin.sqlplaylist');

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'logHandler' => $parameters->{'logHandler'},
		'pluginPrefs' => $parameters->{'pluginPrefs'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'downloadApplicationId' => $parameters->{'downloadApplicationId'},
		'supportDownloadError' => $parameters->{'supportDownloadError'},
		'addSqlErrorCallback' => $parameters->{'addSqlErrorCallback'}
	};

	$self->{'contentDirectoryHandler'} = undef;
	$self->{'templateContentDirectoryHandler'} = undef;
	$self->{'mixDirectoryHandler'} = undef;
	$self->{'templateDirectoryHandler'} = undef;
	$self->{'templateDataDirectoryHandler'} = undef;
	$self->{'contentPluginHandler'} = undef;
	$self->{'mixPluginHandler'} = undef;
	$self->{'templatePluginHandler'} = undef;
	$self->{'parameterHandler'} = undef;
	
	$self->{'templateParser'} = undef;
	$self->{'contentParser'} = undef;
	$self->{'mixParser'} = undef;
	$self->{'templateContentParser'} = undef;

	$self->{'webAdminMethods'} = undef;

	$self->{'templates'} = undef;
	$self->{'items'} = undef;

	bless $self,$class;
	$self->init();
	return $self;
}

sub init {
	my $self = shift;
		my %parserParameters = (
			'pluginId' => $self->pluginId,
			'pluginVersion' => $self->pluginVersion,
			'logHandler' => $self->logHandler,
		);
		$parserParameters{'cacheName'} = "FileCache/SQLPlayList/".$self->pluginVersion."/Templates";
		$self->templateParser(Plugins::SQLPlayList::ConfigManager::TemplateParser->new(\%parserParameters));
		$parserParameters{'cacheName'} = "FileCache/SQLPlayList/".$self->pluginVersion."/Playlists";
		$self->contentParser(Plugins::SQLPlayList::ConfigManager::ContentParser->new(\%parserParameters));

		my %parameters = (
			'logHandler' => $self->logHandler,
			'criticalErrorCallback' => $self->addSqlErrorCallback,
			'parameterPrefix' => 'itemparameter'
		);
		$self->parameterHandler(Plugins::SQLPlayList::ConfigManager::ParameterHandler->new(\%parameters));

		my %directoryHandlerParameters = (
			'logHandler' => $self->logHandler,
			'cacheName' => "FileCache/SQLPlayList/".$self->pluginVersion."/Files",
		);
		$directoryHandlerParameters{'extension'} = "sql.xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->contentDirectoryHandler(Plugins::SQLPlayList::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "sql.xml";
		$directoryHandlerParameters{'identifierExtension'} = "sql.xml";
		$directoryHandlerParameters{'parser'} = $self->templateParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDirectoryHandler(Plugins::SQLPlayList::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "sql.template";
		$directoryHandlerParameters{'identifierExtension'} = "sql.xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDataDirectoryHandler(Plugins::SQLPlayList::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		my %pluginHandlerParameters = (
			'logHandler' => $self->logHandler,
			'pluginId' => $self->pluginId,
		);

		$pluginHandlerParameters{'listMethod'} = "getSQLPlayListTemplates";
		$pluginHandlerParameters{'dataMethod'} = "getSQLPlayListTemplateData";
		$pluginHandlerParameters{'contentType'} = "template";
		$pluginHandlerParameters{'contentParser'} = $self->templateParser;
		$pluginHandlerParameters{'templateContentParser'} = undef;
		$self->templatePluginHandler(Plugins::SQLPlayList::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$parserParameters{'templatePluginHandler'} = $self->templatePluginHandler;
		$parserParameters{'cacheName'} = "FileCache/SQLPlayList/".$self->pluginVersion."/Playlists";
		$self->templateContentParser(Plugins::SQLPlayList::ConfigManager::TemplateContentParser->new(\%parserParameters));

		$directoryHandlerParameters{'extension'} = "sql.values.xml";
		$directoryHandlerParameters{'parser'} = $self->templateContentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->templateContentDirectoryHandler(Plugins::SQLPlayList::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$pluginHandlerParameters{'listMethod'} = "getSQLPlayListPlaylists";
		$pluginHandlerParameters{'dataMethod'} = "getSQLPlayListPlaylistData";
		$pluginHandlerParameters{'contentType'} = "playlist";
		$pluginHandlerParameters{'contentParser'} = $self->contentParser;
		$pluginHandlerParameters{'templateContentParser'} = $self->templateContentParser;
		$self->contentPluginHandler(Plugins::SQLPlayList::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$self->initWebAdminMethods();
}
sub initWebAdminMethods {
	my $self = shift;

	my %webTemplates = (
		'webEditItems' => 'plugins/SQLPlayList/sqlplaylist_list.html',
		'webEditItem' => 'plugins/SQLPlayList/webadminmethods_edititem.html',
		'webEditSimpleItem' => 'plugins/SQLPlayList/webadminmethods_editsimpleitem.html',
		'webNewItem' => 'plugins/SQLPlayList/webadminmethods_newitem.html',
		'webNewSimpleItem' => 'plugins/SQLPlayList/webadminmethods_newsimpleitem.html',
		'webNewItemParameters' => 'plugins/SQLPlayList/webadminmethods_newitemparameters.html',
		'webNewItemTypes' => 'plugins/SQLPlayList/webadminmethods_newitemtypes.html',
		'webDownloadItem' => 'plugins/SQLPlayList/webadminmethods_downloaditem.html',
		'webSaveDownloadedItem' => 'plugins/SQLPlayList/webadminmethods_savedownloadeditem.html',
		'webPublishLogin' => 'plugins/SQLPlayList/webadminmethods_login.html',
		'webPublishRegister' => 'plugins/SQLPlayList/webadminmethods_register.html',
		'webPublishItemParameters' => 'plugins/SQLPlayList/webadminmethods_publishitemparameters.html',
	);

	my @itemDirectories = ();
	my @templateDirectories = ();
	my $dir = $prefs->get("playlist_directory");
	if (defined $dir && -d $dir) {
		push @itemDirectories,$dir
	}
	$dir = $prefs->get("template_directory");
	if (defined $dir && -d $dir) {
		push @templateDirectories,$dir
	}
	my $internalSupportDownloadError = undef;
	if(!defined($dir) || !-d $dir) {
		$internalSupportDownloadError = 'You have to specify a template directory before you can download playlist templates';
	}
	if(defined($self->supportDownloadError)) {
		$internalSupportDownloadError = $self->supportDownloadError;
	}
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if( -d catdir($plugindir,"SQLPlayList","Playlists")) {
			push @itemDirectories, catdir($plugindir,"SQLPlayList","Playlists")
		}
		if( -d catdir($plugindir,"SQLPlayList","Templates")) {
			push @templateDirectories, catdir($plugindir,"SQLPlayList","Templates")
		}
	}
	my %webAdminMethodsParameters = (
		'pluginPrefs' => $self->pluginPrefs,
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'downloadApplicationId' => $self->downloadApplicationId,
		'extension' => 'sql.xml',
		'simpleExtension' => 'sql.values.xml',
		'logHandler' => $self->logHandler,
		'contentPluginHandler' => $self->contentPluginHandler,
		'templatePluginHandler' => $self->templatePluginHandler,
		'contentDirectoryHandler' => $self->contentDirectoryHandler,
		'contentTemplateDirectoryHandler' => $self->templateContentDirectoryHandler,
		'templateDirectoryHandler' => $self->templateDirectoryHandler,
		'templateDataDirectoryHandler' => $self->templateDataDirectoryHandler,
		'parameterHandler' => $self->parameterHandler,
		'contentParser' => $self->contentParser,
		'templateDirectories' => \@templateDirectories,
		'itemDirectories' => \@itemDirectories,
		'customTemplateDirectory' => $prefs->get("template_directory"),
		'customItemDirectory' => $prefs->get("playlist_directory"),
		'supportDownload' => 1,
		'supportDownloadError' => $internalSupportDownloadError,
		'webCallbacks' => $self,
		'webTemplates' => \%webTemplates,
		'downloadUrl' => $prefs->get("download_url")
	);
	$self->webAdminMethods(Plugins::SQLPlayList::ConfigManager::PlaylistWebAdminMethods->new(\%webAdminMethodsParameters));

}

sub readTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	
	my %templates = ();
	my %globalcontext = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir,"SQLPlayList","Templates")."\n");
		next unless -d catdir($plugindir,"SQLPlayList","Templates");
		$globalcontext{'source'} = 'builtin';
		$self->templateDirectoryHandler()->readFromDir($client,catdir($plugindir,"SQLPlayList","Templates"),\%templates,\%globalcontext);
	}

	$globalcontext{'source'} = 'plugin';
	$self->templatePluginHandler()->readFromPlugins($client,\%templates,undef,\%globalcontext);

	my $templateDir = $prefs->get('template_directory');
	$self->logHandler->debug("Checking for dir: $templateDir\n");
	if($templateDir && -d $templateDir) {
		$globalcontext{'source'} = 'custom';
		$self->templateDirectoryHandler()->readFromDir($client,$templateDir,\%templates,\%globalcontext);
	}
	return \%templates;
}

sub readItemConfiguration {
	my $self = shift;
	my $client = shift;
	my $storeInCache = shift;
	
	my $dir = $prefs->get("playlist_directory");
    	$self->logHandler->debug("Searching for item configuration in: $dir\n");
    
	my %items = ();
	my %customItems = ();

	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	my %globalcontext = ();
	$self->templates($self->readTemplateConfiguration());

	$globalcontext{'source'} = 'plugin';
	$globalcontext{'templates'} = $self->templates;

	$self->contentPluginHandler->readFromPlugins($client,\%items,undef,\%globalcontext);
	for my $plugindir (@pluginDirs) {
		$globalcontext{'source'} = 'builtin';
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir,"SQLPlayList","Playlists")."\n");
		if( -d catdir($plugindir,"SQLPlayList","Playlists")) {
			$self->contentDirectoryHandler()->readFromDir($client,catdir($plugindir,"SQLPlayList","Playlists"),\%items,\%globalcontext);
			$self->templateContentDirectoryHandler()->readFromDir($client,catdir($plugindir,"SQLPlayList","Playlists"),\%items, \%globalcontext);
		}
	}
	$self->logHandler->debug("Checking for dir: $dir\n");
	if (!defined $dir || !-d $dir) {
		$self->logHandler->debug("Skipping custom configuration scan - directory is undefined\n");
	}else {
		$globalcontext{'source'} = 'custom';
		$self->contentDirectoryHandler()->readFromDir($client,$dir,\%customItems,\%globalcontext);
		$self->templateContentDirectoryHandler()->readFromDir($client,$dir,\%customItems, \%globalcontext);
		for my $itemId (keys %customItems) {
			if(defined($items{$itemId})) {
				delete($items{$itemId});
			}
		}
	}

	my %localItems = ();
	for my $itemId (keys %items) {
		my $item = $items{$itemId};
		$localItems{$item->{'id'}} = $item;
	}
	for my $itemId (keys %customItems) {
		my $item = $customItems{$itemId};
		$localItems{$item->{'id'}} = $item;
	}

	if($storeInCache) {
		$self->items(\%localItems);
	}
	my %result = (
		'playlists' => \%localItems,
		'templates' => $self->templates
	);
	return \%result;
}

sub changedItemConfiguration {
        my ($self, $client, $params) = @_;
#	Plugins::SQLPlayList::Plugin::initPlayLists($client);
}

sub changedTemplateConfiguration {
        my ($self, $client, $params) = @_;
#	$self->readTemplateConfiguration($client);
}

sub webEditItems {
        my ($self, $client, $params) = @_;

	$params->{'reload'} = 1;
	return Plugins::SQLPlayList::Plugin::handleWebList($client,$params);
}

sub webEditItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'playlists'});
	}
	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	
	return $self->webAdminMethods->webEditItem($client,$params,$params->{'item'},$self->items,$self->templates);	
}


sub webDeleteItemType {
        my ($self, $client, $params) = @_;
	return $self->webAdminMethods->webDeleteItemType($client,$params,$params->{'itemtemplate'});	
}


sub webNewItemTypes {
        my ($self, $client, $params) = @_;

	$self->templates($self->readTemplateConfiguration($client));
	
	return $self->webAdminMethods->webNewItemTypes($client,$params,$self->templates);	
}

sub webNewItemParameters {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates) || !defined($self->templates->{$params->{'itemtemplate'}})) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	return $self->webAdminMethods->webNewItemParameters($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webLogin {
        my ($self, $client, $params) = @_;

	return $self->webAdminMethods->webPublishLogin($client,$params,$params->{'item'});	
}


sub webPublishItemParameters {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'playlists'});
	}

	return $self->webAdminMethods->webPublishItemParameters($client,$params,$params->{'item'},$self->items->{$params->{'item'}}->{'name'},$self->items,$self->templates);	
}

sub webPublishItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'playlists'});
	}

	return $self->webAdminMethods->webPublishItem($client,$params,$params->{'item'},$self->items,$self->templates);	
}

sub webDownloadItems {
        my ($self, $client, $params) = @_;
	return $self->webAdminMethods->webDownloadItems($client,$params);	
}

sub webDownloadNewItems {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}

	return $self->webAdminMethods->webDownloadNewItems($client,$params,$self->templates);	
}

sub webDownloadItem {
        my ($self, $client, $params) = @_;
	return $self->webAdminMethods->webDownloadItem($client,$params,$params->{'itemtemplate'});	
}

sub webNewItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	
	return $self->webAdminMethods->webNewItem($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webSaveSimpleItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	$params->{'items'} = $self->items;
	
	return $self->webAdminMethods->webSaveSimpleItem($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webRemoveItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'playlists'});
	}
	return $self->webAdminMethods->webDeleteItem($client,$params,$params->{'item'},$self->items);	
}

sub webSaveNewSimpleItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	$params->{'items'} = $self->items;
	
	return $self->webAdminMethods->webSaveNewSimpleItem($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webSaveNewItem {
        my ($self, $client, $params) = @_;
	$params->{'items'} = $self->items;
	return $self->webAdminMethods->webSaveNewItem($client,$params);	
}

sub webSaveItem {
        my ($self, $client, $params) = @_;
	$params->{'items'} = $self->items;
	return $self->webAdminMethods->webSaveItem($client,$params);	
}

1;

__END__
