/*
 * Copyright (C) 2017 Matthias Klumpp <matthias@tenstral.net>
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

module laniakea.db.schema.planter;
@safe:

/**
* Configuration specific for the germinate module.
**/
struct PlanterConfig {
   string metaPackageGitSourceUrl; /// Git URL of a Germinator seed
}

import laniakea.db.database;

/**
 * Add/update configuration.
 */
void update (Database db, PlanterConfig conf)
{
    auto conn = db.getConnection ();
    scope (exit) db.dropConnection (conn);

    db.updateConfigEntry (conn, LkModule.PLANTER, "metaPackageGitSourceUrl", conf.metaPackageGitSourceUrl);
}

auto getPlanterConfig (Database db)
{
    auto conn = db.getConnection ();
    scope (exit) db.dropConnection (conn);

    PlanterConfig conf;
    conf.metaPackageGitSourceUrl = db.getConfigEntry!string (conn, LkModule.PLANTER, "metaPackageGitSourceUrl");

    return conf;
}
