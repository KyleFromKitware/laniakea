/*
 * Copyright (C) 2016-2017 Matthias Klumpp <matthias@tenstral.net>
 *
 * Licensed under the GNU Lesser General Public License Version 3
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the license, or
 * (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this software.  If not, see <http://www.gnu.org/licenses/>.
 */

module laniakea.localconfig;
@safe:

import std.stdio;
import std.array : appender, empty;
import std.string : format, toLower, startsWith;
import std.path : dirName, getcwd, buildPath, buildNormalizedPath;
import std.conv : to;
import std.json;
import std.typecons : Nullable;
static import std.file;

import laniakea.logging;
import laniakea.utils : findFilesBySuffix;
import laniakea.pkgitems : VersionPriority;
import laniakea.db.schema.basic;

public immutable laniakeaVersion = "0.1";

/**
 * Information about the derivative's package archive.
 */
struct ArchiveDetails
{
    string rootPath;
    string distroTag;
    DistroSuite develSuite;
    DistroSuite incomingSuite;
}

/**
 * Local configuration specific for the synchrotron tool.
 */
struct LocalSynchrotronConfig
{
    string[] sourceKeyrings;
}

/**
 * Configuration specific for the spears tool.
 */
struct SpearsConfigEntry
{
    string fromSuite;
    string toSuite;

    uint[VersionPriority] delays;
}

/**
 * Configuration specific for the germinate module.
 */
struct EggshellConfig
{
    string metaPackageGitSourceUrl;
}

final class LocalConfig
{
    // Thread local
    private static bool instantiated_;

    // Thread global
    private __gshared LocalConfig instance_;

    @trusted
    static LocalConfig get ()
    {
        if (!instantiated_) {
            synchronized (LocalConfig.classinfo) {
                if (!instance_)
                    instance_ = new LocalConfig ();

                instantiated_ = true;
            }
        }

        return instance_;
    }

    private bool loaded;

    // Public properties
    string projectName;
    string cacheDir;
    string workspace;
    ArchiveDetails archive;

    string databaseName;
    string mongoUrl;

    DistroSuite[] suites;

    LocalSynchrotronConfig synchrotron;

    SpearsConfigEntry[] spears;

    EggshellConfig eggshell;

    private this () { }

    @trusted
    void loadFromFile (string fname)
    in { assert (!loaded); }
    body
    {
        // read the configuration JSON file
        auto f = File (fname, "r");
        auto jsonData = appender!string;
        string line;
        while ((line = f.readln ()) !is null)
            jsonData ~= line;

        JSONValue root = parseJSON (jsonData.data);

        this.projectName = "Unknown";
        if ("ProjectName" in root)
            this.projectName = root["ProjectName"].str;

        cacheDir = "/var/tmp/laniakea";
        if ("CacheLocation" in root)
            cacheDir = root["CacheLocation"].str;

        if ("Archive" !in root)
            throw new Exception ("Configuration must define archive details in an 'Archive' section.");
        if ("Suites" !in root)
            throw new Exception ("Configuration must define suites in a 'Suites' section.");
        if ("Workspace" !in root)
            throw new Exception ("Configuration must define a persistent working directory via 'Workspace'.");

        databaseName = "laniakea";
        mongoUrl = "mongodb://localhost/";
        if ("Database" in root) {
            // read database properties
            if ("mongoUrl" in root["Database"].object)
                mongoUrl = root["Database"]["mongoUrl"].str;
            if ("db" in root["Database"].object)
                databaseName = root["Database"]["db"].str;
        }

        workspace = root["Workspace"].str;
        archive.rootPath = root["Archive"]["path"].str;
        archive.distroTag = root["Archive"]["distroTag"].str;
        auto develSuiteName = root["Archive"]["develSuite"].str;
        auto incomingSuiteName = root["Archive"]["incomingSuite"].str;

        // Suites configuration
        foreach (sname, sdetails; root["Suites"].object) {
            DistroSuite suite;
            suite.name = sname;

            foreach (ref e; sdetails["components"].array)
                suite.components ~= e.str;
            foreach (ref e; sdetails["architectures"].array)
                suite.architectures ~= e.str;

            if (suite.name == develSuiteName)
                archive.develSuite = suite;
            else if (suite.name == incomingSuiteName)
                archive.incomingSuite = suite;

            suites ~= suite;
        }

        // Sanity check
        if (archive.develSuite.name.empty)
            throw new Exception ("Could not find definition of development suite %s.".format (develSuiteName));
        if (archive.incomingSuite.name.empty)
            throw new Exception ("Could not find definition of incoming suite %s.".format (incomingSuiteName));

        // Local synchrotron configuration
        if ("Synchrotron" in root) {
            auto syncConf = root["Synchrotron"];

            if ("SourceKeyringDir" in syncConf) {
                synchrotron.sourceKeyrings = findFilesBySuffix (syncConf["SourceKeyringDir"].str, ".gpg");
            }
        }

        // Spears configuration
        if ("Spears" in root) {
            foreach (ref e; root["Spears"].array) {
                SpearsConfigEntry spc;

                spc.fromSuite = e["from"].str;
                spc.toSuite = e["to"].str;

                spears ~= spc;
            }
        }

        // Eggshell configuration
        if ("Eggshell" in root) {
            auto esConf = root["Eggshell"];

            eggshell.metaPackageGitSourceUrl = esConf["metaPackageGitSourceUrl"].str;
        }

        loaded = true;
    }

    void load ()
    {
        immutable exeDir = dirName (std.file.thisExePath ());

        if (!exeDir.startsWith ("/usr")) {
            immutable resPath = buildNormalizedPath (exeDir, "..", "data", "archive-config.json");
            if (std.file.exists (resPath)) {
                loadFromFile (resPath);
            }
        }

        loadFromFile ("/etc/laniakea/archive-config.json");
    }

    Nullable!DistroSuite getSuite (string name)
    {
        Nullable!DistroSuite res;
        foreach (ref suite; suites) {
            if (suite.name == name) {
                res = suite;
                break;
            }
        }
        return res;
    }
}