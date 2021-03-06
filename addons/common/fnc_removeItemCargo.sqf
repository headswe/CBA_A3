#include "script_component.hpp"
/* ----------------------------------------------------------------------------
Function: CBA_fnc_removeItemCargo

Description:
    Removes specific item(s) from cargo space.

    Warning: All weapon attachments/magazines in containers in container will become detached.
    Warning: Preset weapons without non-preset parents will get their attachments readded (engine limitation).

Parameters:
    _container    - Object with cargo <OBJECT>
    _item         - Classname of item(s) to remove <STRING>
    _count        - Number of item(s) to remove <NUMBER> (Default: 1)
    _keepContents - Keep contents of the removed item (if uniform/vest) <BOOLEAN> (Default: false)

Returns:
    true on success, false otherwise <BOOLEAN>

Examples:
    (begin example)
    // Remove 1 GPS from a box
    _success = [myCoolItemBox, "ItemGPS"] call CBA_fnc_removeItemCargo;

    // Remove 2 Compasses from a box
    _success = [myCoolItemBox, "ItemCompass", 2] call CBA_fnc_removeItemCargo;

    // Remove 1 Vest from a box and keep contents
    _success = [myCoolWeaponBox, "V_PlateCarrier1_rgr", 1, true] call CBA_fnc_removeItemCargo;
    (end)

Author:
    Jonpas
---------------------------------------------------------------------------- */
SCRIPT(removeItemCargo);

params [["_container", objNull, [objNull]], ["_item", "", [""]], ["_count", 1, [0]], ["_keepContents", false, [true]]];

if (isNull _container) exitWith {
    TRACE_2("Container not Object or null",_container,_item);
    false
};

if (_item isEqualTo "") exitWith {
    TRACE_2("Item not String or empty",_container,_item);
    false
};

private _config = _item call CBA_fnc_getItemConfig;

if (isNull _config || {getNumber (_config >> "scope") < 1}) exitWith {
    TRACE_2("Item does not exist in Config",_container,_item);
    false
};

if (_count <= 0) exitWith {
    TRACE_3("Count is not a positive number",_container,_item,_count);
    false
};

// Ensure proper count
_count = round _count;

// Save containers and contents
private _containerData = [];
{
    _x params ["_class", "_object"];
    if !(_object in (everyBackpack _container)) then {
        _containerData pushBack [_class, getItemCargo _object, magazinesAmmoCargo _object, weaponsItemsCargo _object];
    };
} forEach (everyContainer _container); // [["class1", object1], ["class2", object2]]

// Save non-container items
(getItemCargo _container) params ["_allItemsType", "_allItemsCount"]; // [[type1, typeN, ...], [count1, countN, ...]]
{
    private _class = _x;
    private _count = _allItemsCount select _forEachIndex;

    private _sameData = _containerData select {_x select 0 == _class};
    if (_sameData isEqualTo []) then {
        _containerData pushBack [_class, _count];
    };
} forEach _allItemsType;

// Clear cargo space and readd the items as long it's not the type in question
clearItemCargoGlobal _container;

TRACE_1("Old cargo",_containerData);


// Add contents to backpack or box helper function
private _fnc_addContents = {
    params ["_container", "_itemCargo", "_magazinesAmmoCargo", "_weaponsItemsCargo"];

    // Items
    {
        private _itemCount = (_itemCargo select 1) select _forEachIndex;
        _container addItemCargoGlobal [_x, _itemCount];
    } forEach (_itemCargo select 0);

    // Magazines (and their ammo count)
    {
        _container addMagazineAmmoCargo [_x select 0, 1, _x select 1];
    } forEach _magazinesAmmoCargo;

    // Weapons (and their attachments)
    // Put attachments next to weapon, no command to put it directly onto a weapon when weapon is in a container
    {
        _x params ["_weapon", "_muzzle", "_pointer", "_optic", "_magazine", "_magazineGL", "_bipod"];

        // weaponsItems magazineGL does not exist if not loaded (not even as empty array)
        if (count _x < 7) then {
            _bipod = _magazineGL;
            _magazineGL = [];
        };

        _container addWeaponWithAttachmentsCargoGlobal [
            [
                _weapon,
                _muzzle, _pointer, _optic,
                _magazine, _magazineGL,
                _bipod
            ], 1
        ];
    } forEach _weaponsItemsCargo;
};

// Process removal
{
    _x params ["_itemClass", "_itemCargoOrCount", "_magazinesAmmoCargo", "_weaponsItemsCargo"];

    if (_count != 0 && {_itemClass == _item}) then {
        // Process removal
        if (count _x < 4) then {
            // Non-container item
            // Add with new count
            _container addItemCargoGlobal [_itemClass, _itemCargoOrCount - _count]; // Silently fails on 'count < 1'
            TRACE_2("Readding",_itemClass,_itemCargoOrCount - _count);

            _count = 0;
        } else {
            // Container item
            _count = _count - 1;

            if (_keepContents) then {
                [_container, _itemCargoOrCount, _magazinesAmmoCargo, _weaponsItemsCargo] call _fnc_addContents;
            };
        };
    } else {
        // Readd only
        if (count _x < 4) then {
            // Non-container item
            _container addItemCargoGlobal [_itemClass, _itemCargoOrCount];
            TRACE_2("Readding",_itemClass,_itemCargoOrCount);
        } else {
            // Container item
            // Save all containers for finding the one we readd after this
            private _addedContainers = ((everyContainer _container) apply {_x select 1}) - everyBackpack _container;

            // Readd
            private _addedContainer = [_itemClass] call CBA_fnc_getNonPresetClass;
            _container addItemCargoGlobal [_addedContainer, 1];

            // Find just added container and add contents (no command returns reference when adding)
            private _addedContainer = ((((everyContainer _container) apply {_x select 1}) - everyBackpack _container) - _addedContainers) select 0;

            [_addedContainer, _itemCargoOrCount, _magazinesAmmoCargo, _weaponsItemsCargo] call _fnc_addContents;
        };
    };
} forEach _containerData;

(_count == 0)
