#!/usr/bin/env python3
"""
Generate a minimal but valid Xcode project file for RPSBattleSimulator.
Uses MD5-based deterministic UUIDs for each object.
"""

import hashlib
import os

def uuid_for(name: str) -> str:
    """Generate a 24-char hex UUID from a name (deterministic)."""
    h = hashlib.md5(name.encode()).hexdigest().upper()
    return h[:24]

# All Swift source files (flat in RPSBattleSimulator/ folder)
SWIFT_FILES = [
    "RPSBattleSimulatorApp.swift",
    "ContentView.swift",
    "SimulationTypes.swift",
    "SeededRNG.swift",
    "SimulationSettings.swift",
    "SimulationEngine.swift",
    "ThemeManager.swift",
    "AppState.swift",
    "VideoFrameRenderer.swift",
    "ArenaView.swift",
    "VideoExporter.swift",
    "AudioGenerator.swift",
    "BatchExporter.swift",
    "SettingsPanel.swift",
    "BatchExportView.swift",
    "ExportProgressView.swift",
    "BattlePreset.swift",
    "SocialPlatform.swift",
    "KeychainStore.swift",
    "SocialAuthManager.swift",
    "SocialUploader.swift",
]

# UUIDs for structural objects
PROJECT_UUID = uuid_for("PROJECT")
TARGET_UUID = uuid_for("TARGET")
SOURCES_PHASE_UUID = uuid_for("SOURCES_PHASE")
FRAMEWORKS_PHASE_UUID = uuid_for("FRAMEWORKS_PHASE")
RESOURCES_PHASE_UUID = uuid_for("RESOURCES_PHASE")
MAIN_GROUP_UUID = uuid_for("MAIN_GROUP")
PRODUCTS_GROUP_UUID = uuid_for("PRODUCTS_GROUP")
SOURCE_GROUP_UUID = uuid_for("SOURCE_GROUP")
APP_PRODUCT_UUID = uuid_for("APP_PRODUCT")
DEBUG_CONFIG_UUID = uuid_for("DEBUG_CONFIG")
RELEASE_CONFIG_UUID = uuid_for("RELEASE_CONFIG")
TARGET_DEBUG_CONFIG_UUID = uuid_for("TARGET_DEBUG_CONFIG")
TARGET_RELEASE_CONFIG_UUID = uuid_for("TARGET_RELEASE_CONFIG")
PROJ_CONFIG_LIST_UUID = uuid_for("PROJ_CONFIG_LIST")
TARGET_CONFIG_LIST_UUID = uuid_for("TARGET_CONFIG_LIST")
ENTITLEMENTS_REF_UUID = uuid_for("ENTITLEMENTS_REF")
INFO_PLIST_REF_UUID = uuid_for("INFO_PLIST_REF")

# Per-file UUIDs
file_refs = {}     # filename -> fileRef UUID
build_files = {}   # filename -> buildFile UUID

for f in SWIFT_FILES:
    file_refs[f] = uuid_for(f"FILE_REF_{f}")
    build_files[f] = uuid_for(f"BUILD_FILE_{f}")

def gen_pbxproj():
    lines = []
    
    def ln(s=""):
        lines.append(s)
    
    ln("// !$*UTF8*$!")
    ln("{")
    ln("\tarchiveVersion = 1;")
    ln("\tclasses = {")
    ln("\t};")
    ln("\tobjectVersion = 56;")
    ln("\tobjects = {")
    ln()
    
    # PBXBuildFile
    ln("/* Begin PBXBuildFile section */")
    for f in SWIFT_FILES:
        ln(f"\t\t{build_files[f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[f]} /* {f} */; }};")
    ln("/* End PBXBuildFile section */")
    ln()
    
    # PBXFileReference
    ln("/* Begin PBXFileReference section */")
    ln(f"\t\t{APP_PRODUCT_UUID} /* RPSBattleSimulator.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RPSBattleSimulator.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    ln(f"\t\t{INFO_PLIST_REF_UUID} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    ln(f"\t\t{ENTITLEMENTS_REF_UUID} /* RPSBattleSimulator.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = RPSBattleSimulator.entitlements; sourceTree = \"<group>\"; }};")
    for f in SWIFT_FILES:
        ln(f"\t\t{file_refs[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
    ln("/* End PBXFileReference section */")
    ln()
    
    # PBXFrameworksBuildPhase
    ln("/* Begin PBXFrameworksBuildPhase section */")
    ln(f"\t\t{FRAMEWORKS_PHASE_UUID} /* Frameworks */ = {{")
    ln(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    ln(f"\t\t\tbuildActionMask = 2147483647;")
    ln(f"\t\t\tfiles = (")
    ln(f"\t\t\t);")
    ln(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    ln(f"\t\t}};")
    ln("/* End PBXFrameworksBuildPhase section */")
    ln()
    
    # PBXGroup
    ln("/* Begin PBXGroup section */")
    # Main group
    ln(f"\t\t{MAIN_GROUP_UUID} = {{")
    ln(f"\t\t\tisa = PBXGroup;")
    ln(f"\t\t\tchildren = (")
    ln(f"\t\t\t\t{SOURCE_GROUP_UUID} /* RPSBattleSimulator */,")
    ln(f"\t\t\t\t{PRODUCTS_GROUP_UUID} /* Products */,")
    ln(f"\t\t\t);")
    ln(f"\t\t\tsourceTree = \"<group>\";")
    ln(f"\t\t}};")
    # Products group
    ln(f"\t\t{PRODUCTS_GROUP_UUID} /* Products */ = {{")
    ln(f"\t\t\tisa = PBXGroup;")
    ln(f"\t\t\tchildren = (")
    ln(f"\t\t\t\t{APP_PRODUCT_UUID} /* RPSBattleSimulator.app */,")
    ln(f"\t\t\t);")
    ln(f"\t\t\tname = Products;")
    ln(f"\t\t\tsourceTree = \"<group>\";")
    ln(f"\t\t}};")
    # Source group
    ln(f"\t\t{SOURCE_GROUP_UUID} /* RPSBattleSimulator */ = {{")
    ln(f"\t\t\tisa = PBXGroup;")
    ln(f"\t\t\tchildren = (")
    for f in SWIFT_FILES:
        ln(f"\t\t\t\t{file_refs[f]} /* {f} */,")
    ln(f"\t\t\t\t{INFO_PLIST_REF_UUID} /* Info.plist */,")
    ln(f"\t\t\t\t{ENTITLEMENTS_REF_UUID} /* RPSBattleSimulator.entitlements */,")
    ln(f"\t\t\t);")
    ln(f"\t\t\tpath = RPSBattleSimulator;")
    ln(f"\t\t\tsourceTree = \"<group>\";")
    ln(f"\t\t}};")
    ln("/* End PBXGroup section */")
    ln()
    
    # PBXNativeTarget
    ln("/* Begin PBXNativeTarget section */")
    ln(f"\t\t{TARGET_UUID} /* RPSBattleSimulator */ = {{")
    ln(f"\t\t\tisa = PBXNativeTarget;")
    ln(f"\t\t\tbuildConfigurationList = {TARGET_CONFIG_LIST_UUID} /* Build configuration list for PBXNativeTarget \"RPSBattleSimulator\" */;")
    ln(f"\t\t\tbuildPhases = (")
    ln(f"\t\t\t\t{SOURCES_PHASE_UUID} /* Sources */,")
    ln(f"\t\t\t\t{FRAMEWORKS_PHASE_UUID} /* Frameworks */,")
    ln(f"\t\t\t\t{RESOURCES_PHASE_UUID} /* Resources */,")
    ln(f"\t\t\t);")
    ln(f"\t\t\tbuildRules = (")
    ln(f"\t\t\t);")
    ln(f"\t\t\tdependencies = (")
    ln(f"\t\t\t);")
    ln(f"\t\t\tname = RPSBattleSimulator;")
    ln(f"\t\t\tproductName = RPSBattleSimulator;")
    ln(f"\t\t\tproductReference = {APP_PRODUCT_UUID} /* RPSBattleSimulator.app */;")
    ln(f"\t\t\tproductType = \"com.apple.product-type.application\";")
    ln(f"\t\t}};")
    ln("/* End PBXNativeTarget section */")
    ln()
    
    # PBXProject
    ln("/* Begin PBXProject section */")
    ln(f"\t\t{PROJECT_UUID} /* Project object */ = {{")
    ln(f"\t\t\tisa = PBXProject;")
    ln(f"\t\t\tattributes = {{")
    ln(f"\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    ln(f"\t\t\t\tLastSwiftUpdateCheck = 1500;")
    ln(f"\t\t\t\tLastUpgradeCheck = 1500;")
    ln(f"\t\t\t}};")
    ln(f"\t\t\tbuildConfigurationList = {PROJ_CONFIG_LIST_UUID} /* Build configuration list for PBXProject \"RPSBattleSimulator\" */;")
    ln(f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    ln(f"\t\t\tdevelopmentRegion = en;")
    ln(f"\t\t\thasScannedForEncodings = 0;")
    ln(f"\t\t\tknownRegions = (")
    ln(f"\t\t\t\ten,")
    ln(f"\t\t\t\tBase,")
    ln(f"\t\t\t);")
    ln(f"\t\t\tmainGroup = {MAIN_GROUP_UUID};")
    ln(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP_UUID} /* Products */;")
    ln(f"\t\t\tprojectDirPath = \"\";")
    ln(f"\t\t\tprojectRoot = \"\";")
    ln(f"\t\t\ttargets = (")
    ln(f"\t\t\t\t{TARGET_UUID} /* RPSBattleSimulator */,")
    ln(f"\t\t\t);")
    ln(f"\t\t}};")
    ln("/* End PBXProject section */")
    ln()
    
    # PBXResourcesBuildPhase
    ln("/* Begin PBXResourcesBuildPhase section */")
    ln(f"\t\t{RESOURCES_PHASE_UUID} /* Resources */ = {{")
    ln(f"\t\t\tisa = PBXResourcesBuildPhase;")
    ln(f"\t\t\tbuildActionMask = 2147483647;")
    ln(f"\t\t\tfiles = (")
    ln(f"\t\t\t);")
    ln(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    ln(f"\t\t}};")
    ln("/* End PBXResourcesBuildPhase section */")
    ln()
    
    # PBXSourcesBuildPhase
    ln("/* Begin PBXSourcesBuildPhase section */")
    ln(f"\t\t{SOURCES_PHASE_UUID} /* Sources */ = {{")
    ln(f"\t\t\tisa = PBXSourcesBuildPhase;")
    ln(f"\t\t\tbuildActionMask = 2147483647;")
    ln(f"\t\t\tfiles = (")
    for f in SWIFT_FILES:
        ln(f"\t\t\t\t{build_files[f]} /* {f} in Sources */,")
    ln(f"\t\t\t);")
    ln(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    ln(f"\t\t}};")
    ln("/* End PBXSourcesBuildPhase section */")
    ln()
    
    # XCBuildConfiguration
    ln("/* Begin XCBuildConfiguration section */")
    
    # Project Debug
    ln(f"\t\t{DEBUG_CONFIG_UUID} /* Debug */ = {{")
    ln(f"\t\t\tisa = XCBuildConfiguration;")
    ln(f"\t\t\tbuildSettings = {{")
    ln(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    ln(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    ln(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    ln(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    ln(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    ln(f"\t\t\t\tENABLE_TESTABILITY = YES;")
    ln(f"\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    ln(f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    ln(f"\t\t\t\tMAC_OS_X_DEPLOYMENT_TARGET = 13.0;")
    ln(f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    ln(f"\t\t\t\tMTL_FAST_MATH = YES;")
    ln(f"\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    ln(f"\t\t\t\tSDKROOT = macosx;")
    ln(f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    ln(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    ln(f"\t\t\t}};")
    ln(f"\t\t\tname = Debug;")
    ln(f"\t\t}};")
    
    # Project Release
    ln(f"\t\t{RELEASE_CONFIG_UUID} /* Release */ = {{")
    ln(f"\t\t\tisa = XCBuildConfiguration;")
    ln(f"\t\t\tbuildSettings = {{")
    ln(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    ln(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    ln(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    ln(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    ln(f"\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    ln(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    ln(f"\t\t\t\tMAC_OS_X_DEPLOYMENT_TARGET = 13.0;")
    ln(f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
    ln(f"\t\t\t\tMTL_FAST_MATH = YES;")
    ln(f"\t\t\t\tSDKROOT = macosx;")
    ln(f"\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    ln(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
    ln(f"\t\t\t}};")
    ln(f"\t\t\tname = Release;")
    ln(f"\t\t}};")
    
    # Target Debug
    ln(f"\t\t{TARGET_DEBUG_CONFIG_UUID} /* Debug */ = {{")
    ln(f"\t\t\tisa = XCBuildConfiguration;")
    ln(f"\t\t\tbuildSettings = {{")
    ln(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = RPSBattleSimulator/RPSBattleSimulator.entitlements;")
    ln(f"\t\t\t\tCODE_SIGN_IDENTITY = \"-\";")
    ln(f"\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    ln(f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    ln(f"\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    ln(f"\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    ln(f"\t\t\t\tINFOPLIST_FILE = RPSBattleSimulator/Info.plist;")
    ln(f"\t\t\t\tMAC_OS_X_DEPLOYMENT_TARGET = 13.0;")
    ln(f"\t\t\t\tMARKETING_VERSION = 1.0;")
    ln(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \"com.rpsbattle.simulator\";")
    ln(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    ln(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    ln(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    ln(f"\t\t\t}};")
    ln(f"\t\t\tname = Debug;")
    ln(f"\t\t}};")
    
    # Target Release
    ln(f"\t\t{TARGET_RELEASE_CONFIG_UUID} /* Release */ = {{")
    ln(f"\t\t\tisa = XCBuildConfiguration;")
    ln(f"\t\t\tbuildSettings = {{")
    ln(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = RPSBattleSimulator/RPSBattleSimulator.entitlements;")
    ln(f"\t\t\t\tCODE_SIGN_IDENTITY = \"-\";")
    ln(f"\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    ln(f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    ln(f"\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    ln(f"\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    ln(f"\t\t\t\tINFOPLIST_FILE = RPSBattleSimulator/Info.plist;")
    ln(f"\t\t\t\tMAC_OS_X_DEPLOYMENT_TARGET = 13.0;")
    ln(f"\t\t\t\tMARKETING_VERSION = 1.0;")
    ln(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \"com.rpsbattle.simulator\";")
    ln(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    ln(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    ln(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    ln(f"\t\t\t}};")
    ln(f"\t\t\tname = Release;")
    ln(f"\t\t}};")
    
    ln("/* End XCBuildConfiguration section */")
    ln()
    
    # XCConfigurationList
    ln("/* Begin XCConfigurationList section */")
    ln(f"\t\t{PROJ_CONFIG_LIST_UUID} /* Build configuration list for PBXProject \"RPSBattleSimulator\" */ = {{")
    ln(f"\t\t\tisa = XCConfigurationList;")
    ln(f"\t\t\tbuildConfigurations = (")
    ln(f"\t\t\t\t{DEBUG_CONFIG_UUID} /* Debug */,")
    ln(f"\t\t\t\t{RELEASE_CONFIG_UUID} /* Release */,")
    ln(f"\t\t\t);")
    ln(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    ln(f"\t\t\tdefaultConfigurationName = Release;")
    ln(f"\t\t}};")
    ln(f"\t\t{TARGET_CONFIG_LIST_UUID} /* Build configuration list for PBXNativeTarget \"RPSBattleSimulator\" */ = {{")
    ln(f"\t\t\tisa = XCConfigurationList;")
    ln(f"\t\t\tbuildConfigurations = (")
    ln(f"\t\t\t\t{TARGET_DEBUG_CONFIG_UUID} /* Debug */,")
    ln(f"\t\t\t\t{TARGET_RELEASE_CONFIG_UUID} /* Release */,")
    ln(f"\t\t\t);")
    ln(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    ln(f"\t\t\tdefaultConfigurationName = Release;")
    ln(f"\t\t}};")
    ln("/* End XCConfigurationList section */")
    ln()
    
    ln("\t};")
    ln(f"\trootObject = {PROJECT_UUID} /* Project object */;")
    ln("}")
    
    return "\n".join(lines)


if __name__ == "__main__":
    output_dir = os.path.join(os.path.dirname(__file__), "..", "RPSBattleSimulator.xcodeproj")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "project.pbxproj")
    
    content = gen_pbxproj()
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)
    
    print(f"Generated: {output_path}")
    print(f"Files included: {len(SWIFT_FILES)}")
    for f in SWIFT_FILES:
        print(f"  {f}")
