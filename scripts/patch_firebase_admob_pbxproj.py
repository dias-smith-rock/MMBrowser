#!/usr/bin/env python3
"""Add Firebase/AdMob source files + SPM packages to MMBrowser.xcodeproj."""
from __future__ import annotations

import re
import uuid
from pathlib import Path

ROOT = Path("/Users/rock/Documents/Code/MMBrowser")
PBX = ROOT / "MMBrowser.xcodeproj" / "project.pbxproj"

def nid(prefix: str) -> str:
    return prefix + uuid.uuid4().hex[:16].upper()

# Stable IDs for reproducibility
IDS = {
    "group_firebase": "FBASEGRP01010101010101",
    "group_ads": "ADS00GRP01010101010101",
    # files: (fileRef, buildFile, path, group_key)
}

FILES = [
    ("FBASEFR01010101010101", "FBASEBF01010101010101", "FirebaseBootstrap.swift", "firebase"),
    ("FBASEFR01010101010102", "FBASEBF01010101010102", "AppAnalytics.swift", "firebase"),
    ("FBASEFR01010101010103", "FBASEBF01010101010103", "RemoteConfigManager.swift", "firebase"),
    ("ADS00FR01010101010101", "ADS00BF01010101010101", "AdMobConfig.swift", "ads"),
    ("ADS00FR01010101010102", "ADS00BF01010101010102", "AdConsentManager.swift", "ads"),
    ("ADS00FR01010101010103", "ADS00BF01010101010103", "AppOpenAdManager.swift", "ads"),
    ("ADS00FR01010101010104", "ADS00BF01010101010104", "HotStartAdManager.swift", "ads"),
    ("ADS00FR01010101010105", "ADS00BF01010101010105", "AdLifecycleCoordinator.swift", "ads"),
    ("ADS00FR01010101010106", "ADS00BF01010101010106", "UIApplicationTopViewController.swift", "ads"),
]

# SPM
PKG_FIREBASE = "SPMPKGFIREBASE01010101"
PKG_GMA = "SPMPKGGMA010101010101"
PKG_UMP = "SPMPKGUMP010101010101"

PRODUCTS = [
    # (productDepID, buildFileID, packageID, productName)
    ("SPMPRDFA010101010101", "SPMBFFA01010101010101", PKG_FIREBASE, "FirebaseAnalytics"),
    ("SPMPRDRC010101010101", "SPMBFRC01010101010101", PKG_FIREBASE, "FirebaseRemoteConfig"),
    ("SPMPRDCL010101010101", "SPMBFCL01010101010101", PKG_FIREBASE, "FirebaseCrashlytics"),
    ("SPMPRDGMA0101010101", "SPMBFGMA010101010101", PKG_GMA, "GoogleMobileAds"),
    ("SPMPRDUMP0101010101", "SPMBFUMP010101010101", PKG_UMP, "GoogleUserMessagingPlatform"),
]

text = PBX.read_text()

# Skip if already patched
if "AdLifecycleCoordinator.swift" in text and "FirebaseAnalytics" in text and "XCRemoteSwiftPackageReference" in text:
    print("Already patched")
    raise SystemExit(0)

# --- PBXBuildFile entries for sources ---
build_files = []
file_refs = []
for fr, bf, name, _ in FILES:
    build_files.append(f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};\n")
    file_refs.append(f"\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n")

# SPM build files
for prod_id, bf_id, pkg_id, pname in PRODUCTS:
    build_files.append(
        f"\t\t{bf_id} /* {pname} in Frameworks */ = {{isa = PBXBuildFile; productRef = {prod_id} /* {pname} */; }};\n"
    )

# Insert before End PBXBuildFile
text = text.replace(
    "/* End PBXBuildFile section */",
    "".join(build_files) + "/* End PBXBuildFile section */",
    1,
)

# Insert file refs before End PBXFileReference
text = text.replace(
    "/* End PBXFileReference section */",
    "".join(file_refs) + "/* End PBXFileReference section */",
    1,
)

# Groups
firebase_children = "".join(f"\t\t\t\t{fr} /* {name} */,\n" for fr, _, name, g in FILES if g == "firebase")
ads_children = "".join(f"\t\t\t\t{fr} /* {name} */,\n" for fr, _, name, g in FILES if g == "ads")

groups = f"""
		{IDS['group_firebase']} /* Firebase */ = {{
			isa = PBXGroup;
			children = (
{firebase_children}\t\t\t);
			path = Firebase;
			sourceTree = "<group>";
		}};
		{IDS['group_ads']} /* Ads */ = {{
			isa = PBXGroup;
			children = (
{ads_children}\t\t\t);
			path = Ads;
			sourceTree = "<group>";
		}};
"""

text = text.replace("/* End PBXGroup section */", groups + "/* End PBXGroup section */", 1)

# Add groups to MMBrowser group children (after Common)
text = text.replace(
    "\t\t\t\tD1A5510B1493499DB371F870 /* Common */,\n",
    "\t\t\t\tD1A5510B1493499DB371F870 /* Common */,\n"
    f"\t\t\t\t{IDS['group_firebase']} /* Firebase */,\n"
    f"\t\t\t\t{IDS['group_ads']} /* Ads */,\n",
    1,
)

# Sources build phase — find MMBrowser Sources section
# 84E6B60C29CD567E001723AE /* Sources */
src_marker = "\t\t84E6B60C29CD567E001723AE /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
if src_marker not in text:
    raise SystemExit("Sources phase not found")
src_entries = "".join(f"\t\t\t\t{bf} /* {name} in Sources */,\n" for _, bf, name, _ in FILES)
text = text.replace(src_marker, src_marker + src_entries, 1)

# Frameworks phase
fw_marker = "\t\t84E6B60D29CD567E001723AE /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
fw_entries = "".join(f"\t\t\t\t{bf} /* {pname} in Frameworks */,\n" for _, bf, _, pname in PRODUCTS)
if fw_marker not in text:
    raise SystemExit("Frameworks phase not found")
text = text.replace(fw_marker, fw_marker + fw_entries, 1)

# Native target packageProductDependencies
old_target = """\t\t84E6B60F29CD567E001723AE /* MMBrowser */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 84E6B62429CD5680001723AE /* Build configuration list for PBXNativeTarget "MMBrowser" */;
			buildPhases = (
				73036A37A4EA493EACF73FFC /* [CP] Check Pods Manifest.lock */,
				84E6B60C29CD567E001723AE /* Sources */,
				84E6B60D29CD567E001723AE /* Frameworks */,
				84E6B60E29CD567E001723AE /* Resources */,
				PWD0007D49CD5C2F814C4 /* Embed Foundation Extensions */,
				24F45F471C0BFCBFDE17C8F0 /* [CP] Embed Pods Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				PWD00033C4286C5ADC689 /* PBXTargetDependency */,
			);
			name = MMBrowser;
			productName = MMBrowser;
			productReference = 84E6B61029CD567E001723AE /* MMBrowser.app */;
			productType = "com.apple.product-type.application";
		};"""

prod_deps = "".join(f"\t\t\t\t{pid} /* {pname} */,\n" for pid, _, _, pname in PRODUCTS)
# Insert Crashlytics run script phase
crash_phase = "FBASECRASHPHASE010101 /* [Firebase] Crashlytics */"

new_target = f"""\t\t84E6B60F29CD567E001723AE /* MMBrowser */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = 84E6B62429CD5680001723AE /* Build configuration list for PBXNativeTarget "MMBrowser" */;
			buildPhases = (
				73036A37A4EA493EACF73FFC /* [CP] Check Pods Manifest.lock */,
				84E6B60C29CD567E001723AE /* Sources */,
				84E6B60D29CD567E001723AE /* Frameworks */,
				84E6B60E29CD567E001723AE /* Resources */,
				PWD0007D49CD5C2F814C4 /* Embed Foundation Extensions */,
				24F45F471C0BFCBFDE17C8F0 /* [CP] Embed Pods Frameworks */,
				{crash_phase},
			);
			buildRules = (
			);
			dependencies = (
				PWD00033C4286C5ADC689 /* PBXTargetDependency */,
			);
			name = MMBrowser;
			packageProductDependencies = (
{prod_deps}\t\t\t);
			productName = MMBrowser;
			productReference = 84E6B61029CD567E001723AE /* MMBrowser.app */;
			productType = "com.apple.product-type.application";
		}};"""

if old_target not in text:
    raise SystemExit("Native target block not found exactly")
text = text.replace(old_target, new_target, 1)

# Crashlytics shell script build phase
crash_script = f"""
		{crash_phase} = {{
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"${{DWARF_DSYM_FOLDER_PATH}}/${{DWARF_DSYM_FILE_NAME}}/Contents/Resources/DWARF/${{TARGET_NAME}}",
				"$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)",
			);
			name = "[Firebase] Crashlytics";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "if [ -f \\"${{BUILD_DIR%/Build/*}}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run\\" ]; then\\n  \\"${{BUILD_DIR%/Build/*}}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run\\"\\nelif [ -f \\"${{PODS_ROOT}}/FirebaseCrashlytics/run\\" ]; then\\n  \\"${{PODS_ROOT}}/FirebaseCrashlytics/run\\"\\nelse\\n  echo \\"note: Firebase Crashlytics run script not found (SPM/Pods) — skip\\"\\nfi\\n";
		}};
"""

text = text.replace(
    "/* End PBXShellScriptBuildPhase section */",
    crash_script + "/* End PBXShellScriptBuildPhase section */",
    1,
)

# Project packageReferences
old_project_tail = """\t\t\tprojectDirPath = "";
			projectRoot = "";
			targets = (
				84E6B60F29CD567E001723AE /* MMBrowser */,
				PWD00064D9F014F9D8741 /* MMBrowserCredentialProvider */,
			);
		};"""

new_project_tail = f"""\t\t\tpackageReferences = (
				{PKG_FIREBASE} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */,
				{PKG_GMA} /* XCRemoteSwiftPackageReference "swift-package-manager-google-mobile-ads" */,
				{PKG_UMP} /* XCRemoteSwiftPackageReference "swift-package-manager-google-user-messaging-platform" */,
			);
			projectDirPath = "";
			projectRoot = "";
			targets = (
				84E6B60F29CD567E001723AE /* MMBrowser */,
				PWD00064D9F014F9D8741 /* MMBrowserCredentialProvider */,
			);
		}};"""

if old_project_tail not in text:
    raise SystemExit("Project tail not found")
text = text.replace(old_project_tail, new_project_tail, 1)

# Package sections at end before closing
package_section = f"""
/* Begin XCRemoteSwiftPackageReference section */
		{PKG_FIREBASE} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/firebase/firebase-ios-sdk.git";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 11.0.0;
			}};
		}};
		{PKG_GMA} /* XCRemoteSwiftPackageReference "swift-package-manager-google-mobile-ads" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/googleads/swift-package-manager-google-mobile-ads.git";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 11.0.0;
			}};
		}};
		{PKG_UMP} /* XCRemoteSwiftPackageReference "swift-package-manager-google-user-messaging-platform" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/googleads/swift-package-manager-google-user-messaging-platform.git";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 2.0.0;
			}};
		}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
"""

for prod_id, _, pkg_id, pname in PRODUCTS:
    package_section += f"""\t\t{prod_id} /* {pname} */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {pkg_id};
			productName = {pname};
		}};
"""

package_section += "/* End XCSwiftPackageProductDependency section */\n"

text = text.replace(
    "\t};\n}",
    "\t};\n" + package_section + "}\n",
    1,
)

PBX.write_text(text)
print("Patched project.pbxproj successfully")
