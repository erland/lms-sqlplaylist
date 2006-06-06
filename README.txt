1. LICENSE
==========
Copyright (C) 2006 Erland Isaksson (erland_i@hotmail.com)

Portions of code derived from the Random Mix plugin:
Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
New world order by Dan Sully - <dan | at | slimdevices.com>
Fairly substantial rewrite by Max Spicer

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

2. PREREQUISITES
================
- A slimserver 6.2.* or 6.5 installed and configured
- The DynamicPlayList plugin must installed

3. FILES
========
This archive should contain the following files:
- readme.txt (this file)
- license.txt (the license)
- *.pm (The application itself)

4. INSTALLATION
===============
Unzip to the Plugins directory in the Slimserver installation.

5. USAGE
========
This plugin makes it possible to create smartplaylists based on SQL queries.
The playlists are continous and will run forever in the same way as the Random Mix plugin.

First you will have to configure a SQLPlayList playlist directory in the plugins
section of the slimserver settings web interface. After this is done you are ready to
create your smart playlists as described below.

To add a playlist you:
1. Create a file with .sql extension (The contents is described below)
2. Put the sql file in the configured SQLPlayList playlist directory
3. Navigate to the SQLPlayList plugin menu on the Squeezebox and select the playlist and start playing, or use the SQL PlayList plugin menu in the web interface.

The SQLPlayList sql file for a playlist must have the following syntax:
- First row: The name of the playlist (This text will be shown for the playlist in the Squeezebox menu for SQLPlayList plugin). 
             This first row can also as the examples begin with: -- PlaylistName: 
- Other rows: SQL queries, all queries will be executed and those starting with SELECT must return a single "url" column and the 
              tracks returned in all SELECT statements will be part of the playlist.

Some example playlists follows below, observere that the SQL statements needs to be different for the standard slimserver database(SQLite) and
for the MySQL database. So make sure you use the right example based on which database you are using. The main difference for simple queries is
that SQLite uses "order by random()" while MySQL uses "order by rand()".

Playlist1.sql: MySQL (Tracks never played)
-----------------------------------------------
-- PlaylistName: Not played tracks
select url from tracks where audio=1 and playCount is null order by rand() limit 10;

Playlist2.sql: SQLite (Tracks never played)
------------------------------------------------
-- PlaylistName: Not played tracks
select url from tracks where audio=1 and playCount is null order by random() limit 10;

Playlist3.sql: MySQL (Tracks rated as 4-5 in TrackStat, requires TrackStat plugin)
---------------------------------------------------------------------------------
-- PlaylistName: Top rated tracks
select tracks.url from track_statistics,tracks,albums where tracks.album=albums.id and tracks.url=track_statistics.url and track_statistics.rating>=80 and tracks.audio=1 order by rand() limit 10;

Playlist4.sql: SQLite (Tracks rated as 4-5 in TrackStat, requires TrackStat plugin)
---------------------------------------------------------------------------------
-- PlaylistName: Top rated tracks
select tracks.url from track_statistics,tracks,albums where tracks.album=albums.id and tracks.url=track_statistics.url and track_statistics.rating>=80 and tracks.audio=1 order by random() limit 10;

Playlist5.sql: MySQL (All tracks besides those which contains genre=Christmas and some bad albums)
-------------------------------------------------------------------------------------------------
-- PlaylistName: Mixed without Christmas

create temporary table genre_track_withname (primary key (track,genre)) select genre_track.track,genre_track.genre,genres.namesort from genre_track,genres where genre_track.genre=genres.id;
create temporary table tracks_nochristmas (primary key (id)) select distinct tracks.id,tracks.title,tracks.url,tracks.album from tracks left join genre_track_withname on tracks.id=genre_track_withname.track and genre_track_withname.namesort='CHRISTMAS' where genre_track_withname.track is null and tracks.audio=1 order by tracks.title;
create temporary table albums_nobad (primary key (id)) select albums.id from albums,tracks_nochristmas,contributor_track where tracks_nochristmas.album=albums.id and tracks_nochristmas.id=contributor_track.track and albums.title not in ('Music Of The Movies - The Love Songs','Piano moods','Love Themes Of The Pan Pipes') group by (albums.id) having count(distinct contributor_track.contributor)<4 order by id;

select tracks_nochristmas.url from tracks_nochristmas,albums_nobad where tracks_nochristmas.album=albums_nobad.id order by rand() limit 10;

drop temporary table genre_track_withname;
drop temporary table tracks_nochristmas;
drop temporary table albums_nobad;

