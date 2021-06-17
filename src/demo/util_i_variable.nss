// -----------------------------------------------------------------------------
//    File: util_i_data.nss
//  System: PW Administration (identity and data management)
// -----------------------------------------------------------------------------
// Description:
//  Include for primary data control functions.
// -----------------------------------------------------------------------------
// Builder Use:
//  This include should be "included" in just about every script in the system.
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
//                              Configuration
// -----------------------------------------------------------------------------

// If you want to set game object variables persistently, set this to TRUE.  If you
// want game object variables to be volatile (original bioware behavior), set this
// to FALSE
const int VARIABLE_GAME_OBJECT_SQLITE = FALSE;

// Set this variable to the name of the table in the sqlite database table that will
// hold all persistent variables
const string VARIABLE_TABLE_NAME = "variables";

// -----------------------------------------------------------------------------
//                              Function Prototypes
// -----------------------------------------------------------------------------

object oModule1 = GetModule();

const int VARIABLE_TYPE_ALL          = 0;
const int VARIABLE_TYPE_INT          = 1;
const int VARIABLE_TYPE_FLOAT        = 2;
const int VARIABLE_TYPE_STRING       = 4;
const int VARIABLE_TYPE_OBJECT       = 8;
const int VARIABLE_TYPE_VECTOR       = 16;
const int VARIABLE_TYPE_LOCATION     = 32;

const int VARIABLE_MODE_SELECT       = 1;
const int VARIABLE_MODE_INSERT       = 2;
const int VARIABLE_MODE_DELETE       = 3;

// ---< Variable Management >---

// ---< [_Get|_Set|_Delete]Local[Int|Float|String|Object|Location|Vector] >---
/* Module-level functions intended to replace and/or supplement Bioware's
    variable handling functions.  These functions will save all variable
    set to any PC or to the GetModule() object persistently in organic
    SQLite databases.  Optionally, variables set on other game objects can
    be saved persistently.
*/
int      _GetLocalInt        (object oObject, string sVarName);
float    _GetLocalFloat      (object oObject, string sVarName);
string   _GetLocalString     (object oObject, string sVarName);
object   _GetLocalObject     (object oObject, string sVarName);
location _GetLocalLocation   (object oObject, string sVarName);
vector   _GetLocalVector     (object oObject, string sVarName);

void     _SetLocalInt        (object oObject, string sVarName, int      nValue);
void     _SetLocalFloat      (object oObject, string sVarName, float    fValue);
void     _SetLocalString     (object oObject, string sVarName, string   sValue);
void     _SetLocalObject     (object oObject, string sVarName, object   oValue);
void     _SetLocalLocation   (object oObject, string sVarName, location lValue);
void     _SetLocalVector     (object oObject, string sVarName, vector   vValue);

void     _DeleteLocalInt     (object oObject, string sVarName);
void     _DeleteLocalFloat   (object oObject, string sVarName);
void     _DeleteLocalString  (object oObject, string sVarName);
void     _DeleteLocalObject  (object oObject, string sVarName);
void     _DeleteLocalLocation(object oObject, string sVarName);
void     _DeleteLocalVector  (object oObject, string sVarName);

// -----------------------------------------------------------------------------
//                             Function Definitions
// -----------------------------------------------------------------------------

string __LocationToString(location l)
{
    //string sAreaId = ObjectToString(GetAreaFromLocation(l)));
    string sAreaId = GetTag(GetAreaFromLocation(l));
    vector vPosition = GetPositionFromLocation(l);
    float fFacing = GetFacingFromLocation(l);

    return "#A#" + sAreaId +
           "#X#" + FloatToString(vPosition.x, 0, 5) +
           "#Y#" + FloatToString(vPosition.y, 0, 5) +
           "#Z#" + FloatToString(vPosition.z, 0, 5) +
           "#F#" + FloatToString(fFacing, 0, 5) + "#";
}

location __StringToLocation(string sLocation)
{
    location l;
    int nLength = GetStringLength(sLocation);

    if (nLength > 0)
    {
        int nPos, nCount;

        nPos = FindSubString(sLocation, "#A#") + 3;
        nCount = FindSubString(GetSubString(sLocation, nPos, nLength - nPos), "#");
        object oArea = StringToObject(GetSubString(sLocation, nPos, nCount));

        nPos = FindSubString(sLocation, "#X#") + 3;
        nCount = FindSubString(GetSubString(sLocation, nPos, nLength - nPos), "#");
        float fX = StringToFloat(GetSubString(sLocation, nPos, nCount));

        nPos = FindSubString(sLocation, "#Y#") + 3;
        nCount = FindSubString(GetSubString(sLocation, nPos, nLength - nPos), "#");
        float fY = StringToFloat(GetSubString(sLocation, nPos, nCount));

        nPos = FindSubString(sLocation, "#Z#") + 3;
        nCount = FindSubString(GetSubString(sLocation, nPos, nLength - nPos), "#");
        float fZ = StringToFloat(GetSubString(sLocation, nPos, nCount));

        vector vPosition = Vector(fX, fY, fZ);

        nPos = FindSubString(sLocation, "#F#") + 3;
        nCount = FindSubString(GetSubString(sLocation, nPos, nLength - nPos), "#");
        float fOrientation = StringToFloat(GetSubString(sLocation, nPos, nCount));

        if (GetIsObjectValid(oArea))
            l = Location(oArea, vPosition, fOrientation);
        else
            l = GetStartingLocation();
    }

    return l;
}

void CreateVariablesTable(object oObject)
{
    int nPC = GetIsPC(oObject);
    string sVarName = (nPC ? "PLAYER" : "MODULE");

    if (GetLocalInt(GetModule(), sVarName + "_INITIALIZED"))
        return;

    SetLocalInt(GetModule(), sVarName + "_INITIALIZED", TRUE);

    string query = "CREATE TABLE IF NOT EXISTS " + VARIABLE_TABLE_NAME + " (" +
        (nPC ? "" : "object TEXT, ") +
        "type INTEGER, " +
        "varname TEXT, " +
        "value TEXT, " +
        "timestamp INTEGER, " +
        "PRIMARY KEY(" + (nPC ? "" : "object, ") + "type, varname));";

    sqlquery sql = SqlPrepareQueryObject((nPC ? oObject : GetModule()), query);
    SqlStep(sql);
}

sqlquery PrepareQuery(object oObject, int nVarType, string sVarName, int nMode)
{
    CreateVariablesTable(oObject);
    int nPC = GetIsPC(oObject);    
    string query;

    switch (nMode)
    {
        case VARIABLE_MODE_SELECT:
            query = "SELECT value FROM " + VARIABLE_TABLE_NAME + " " +
                "WHERE " + (nPC ? "" : "object = @object AND ") + "type = @type AND varname = @varname;";
            break;
        case VARIABLE_MODE_INSERT:
            query = "INSERT INTO " + VARIABLE_TABLE_NAME + " " +
                "(" + (nPC ? "" : "object, ") + "type, varname, value, timestamp) " +
                "VALUES (" + (nPC ? "" : "@object, ") + "@type, @varname, @value, strftime('%s','now')) " +
                "ON CONFLICT (" + (nPC ? "" : "object, ") + "type, varname) DO UPDATE SET value = @value, timestamp = strftime('%s','now');";
            break;
        case VARIABLE_MODE_DELETE:
            query = "DELETE FROM " + VARIABLE_TABLE_NAME + " " +
                "WHERE " + (nPC ? "" : "object = @object AND ") + "type = @type AND varname = @varname;";
            break;
    }
    
    sqlquery sql = SqlPrepareQueryObject((nPC ? oObject : GetModule()), query);
    if (!nPC)
        SqlBindString(sql, "@object", ObjectToString(oObject));

    SqlBindInt(sql, "@type", nVarType);
    SqlBindString(sql, "@varname", sVarName);

    return sql;
}

// ---< _GetLocal* Variable Procedures >---

int _GetLocalInt(object oObject, string sVarName)
{
    if (sVarName == "")
        return 0;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;
    
    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_INT, sVarName, VARIABLE_MODE_SELECT);

        if (SqlStep(sql))
            return SqlGetInt(sql, 0);
        else
            return 0;
    }
    else
        return GetLocalInt(oObject, sVarName);
}

float _GetLocalFloat(object oObject, string sVarName)
{
    if (sVarName == "")
        return 0.0;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;
    
    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_FLOAT, sVarName, VARIABLE_MODE_SELECT);

        if (SqlStep(sql))
            return SqlGetFloat(sql, 0);
        else
            return 0.0;
    }
    else
        return GetLocalFloat(oObject, sVarName);
}

string _GetLocalString(object oObject, string sVarName)
{
    if (sVarName == "")
        return "";

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;
    
    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_STRING, sVarName, VARIABLE_MODE_SELECT);

        if (SqlStep(sql))
            return SqlGetString(sql, 0);
        else
            return "";
    }
    else
        return GetLocalString(oObject, sVarName);
}

object _GetLocalObject(object oObject, string sVarName)
{
    if (sVarName == "")
        return OBJECT_INVALID;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;
    
    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_OBJECT, sVarName, VARIABLE_MODE_SELECT);

        if (SqlStep(sql))
            return StringToObject(SqlGetString(sql, 0));
        else
            return OBJECT_INVALID;
    }
    else
        return GetLocalObject(oObject, sVarName);
}

location _GetLocalLocation(object oObject, string sVarName)
{
    if (sVarName == "")
        return GetStartingLocation();

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;
    
    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_LOCATION, sVarName, VARIABLE_MODE_SELECT);

        if (SqlStep(sql))
            return __StringToLocation(SqlGetString(sql, 0));
        else
            return GetStartingLocation();
    }
    else
        return GetLocalLocation(oObject, sVarName);
}

vector _GetLocalVector(object oObject, string sVarName)
{
    if (sVarName == "")
        return Vector();

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;
    
    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_VECTOR, sVarName, VARIABLE_MODE_SELECT);

        if (SqlStep(sql))
            return SqlGetVector(sql, 0);
        else
            return Vector();
    }
    else
        return GetPositionFromLocation(GetLocalLocation(oObject, "V:" + sVarName));
}

// ---< _SetLocal* Variable Procedures >---

void _SetLocalInt(object oObject, string sVarName, int nValue)
{
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_INT, sVarName, VARIABLE_MODE_INSERT);
        SqlBindInt(sql, "@value", nValue);
        SqlStep(sql);
    }
    else
        SetLocalInt(oObject, sVarName, nValue);
}

void _SetLocalFloat(object oObject, string sVarName, float fValue)
{
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_FLOAT, sVarName, VARIABLE_MODE_INSERT);
        SqlBindFloat(sql, "@value", fValue);
        SqlStep(sql);
    }
    else
        SetLocalFloat(oObject, sVarName, fValue);
}

void _SetLocalString(object oObject, string sVarName, string sValue)
{
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_STRING, sVarName, VARIABLE_MODE_INSERT);
        SqlBindString(sql, "@value", sValue);
        SqlStep(sql);
    }
    else
        SetLocalString(oObject, sVarName, sValue);
}

void _SetLocalObject(object oObject, string sVarName, object oValue)
{
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_OBJECT, sVarName, VARIABLE_MODE_INSERT);
        SqlBindString(sql, "@value", ObjectToString(oValue));
        SqlStep(sql);
    }
    else
        SetLocalObject(oObject, sVarName, oValue);
}

void _SetLocalLocation(object oObject, string sVarName, location lValue)
{
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_LOCATION, sVarName, VARIABLE_MODE_INSERT);
        SqlBindString(sql, "@value", __LocationToString(lValue));
        SqlStep(sql);
    }
    else
        SetLocalLocation(oObject, sVarName, lValue);
}

void _SetLocalVector(object oObject, string sVarName, vector vValue)
{
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_LOCATION, sVarName, VARIABLE_MODE_INSERT);
        SqlBindVector(sql, "@value", vValue);
        SqlStep(sql);
    }
    else
        SetLocalLocation(oObject, "V:" + sVarName, Location(OBJECT_INVALID, vValue, 0.0f));
}

// ---< _DeleteLocal* Variable Procedures >---

void _DeleteLocalInt(object oObject, string sVarName)
{    
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_INT, sVarName, VARIABLE_MODE_DELETE);
        SqlStep(sql);
    }
    else
        DeleteLocalInt(oObject, sVarName);
}

void _DeleteLocalFloat(object oObject, string sVarName)
{    
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_FLOAT, sVarName, VARIABLE_MODE_DELETE);
        SqlStep(sql);
    }
    else
        DeleteLocalFloat(oObject, sVarName);
}

void _DeleteLocalString(object oObject, string sVarName)
{    
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_STRING, sVarName, VARIABLE_MODE_DELETE);
        SqlStep(sql);
    }
    else
        DeleteLocalString(oObject, sVarName);
}

void _DeleteLocalObject(object oObject, string sVarName)
{    
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_OBJECT, sVarName, VARIABLE_MODE_DELETE);
        SqlStep(sql);
    }
    else
        DeleteLocalObject(oObject, sVarName);
}

void _DeleteLocalLocation(object oObject, string sVarName)
{    
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_LOCATION, sVarName, VARIABLE_MODE_DELETE);
        SqlStep(sql);
    }
    else
        DeleteLocalLocation(oObject, sVarName);
}

void _DeleteLocalVector(object oObject, string sVarName)
{    
    if (sVarName == "")
        return;

    if (oObject == OBJECT_INVALID)
        oObject = oModule1;

    if (VARIABLE_GAME_OBJECT_SQLITE || GetIsPC(oObject) || oObject == oModule1)
    {
        sqlquery sql = PrepareQuery(oObject, VARIABLE_TYPE_VECTOR, sVarName, VARIABLE_MODE_DELETE);
        SqlStep(sql);
    }
    else
        DeleteLocalLocation(oObject, "V:" + sVarName);
}
