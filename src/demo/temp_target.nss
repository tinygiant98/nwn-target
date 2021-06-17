
#include "util_i_target"
#include "util_i_variable"

const string TARGET_HOOK_VARNAME = "TARGET_HOOK_VARNAME";

void main()
{
    object oPC = OBJECT_SELF;
    int n, nCount = TS_CountTargetingHookTargets(oPC, TARGET_HOOK_VARNAME);

    Notice("Targeting process complete: " + IntToString(nCount) + " target" + (nCount == 1 ? "" : "s") + " saved");

    sqlquery sqlTargets = TS_GetTargetList(oPC, TARGET_HOOK_VARNAME);
    while (SqlStep(sqlTargets))
    {
        object oTarget = StringToObject(SqlGetString(sqlTargets, 0));
        object oArea = StringToObject(SqlGetString(sqlTargets, 1));
        vector vTarget = SqlGetVector(sqlTargets, 2);

        location lTarget = Location(oArea, vTarget, 0.0);

        Notice("  Target #" + HexColorString(IntToString(n++), COLOR_CYAN) +
               "\n    Target Tag -> " + (GetIsPC(oTarget) ? HexColorString(GetName(oTarget), COLOR_GREEN_LIGHT) : HexColorString(GetTag(oTarget), COLOR_CYAN)) +
               "\n    Target Location -> " + HexColorString(__LocationToString(lTarget), COLOR_CYAN) +
               "\n    Target Position -> " + HexColorString("(" + FloatToString(vTarget.x, 3, 1) + ", " +
                                              FloatToString(vTarget.y, 3, 1) + ", " +
                                              FloatToString(vTarget.z, 3, 1) + ")", COLOR_CYAN));
    }

    TS_DeleteTargetList(oPC, TARGET_HOOK_VARNAME);
}
