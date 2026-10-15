#!/usr/bin/env python3
"""Add SPM package refs with 24-char HEX UUIDs. Run AFTER pod install."""
from pathlib import Path

PBX = Path("/Users/rock/Documents/Code/MMBrowser/MMBrowser.xcodeproj/project.pbxproj")
text = PBX.read_text()

if "XCRemoteSwiftPackageReference" in text and "FirebaseAnalytics" in text:
    print("SPM already present")
    raise SystemExit(0)

PKG_FIREBASE = "A11F1BEBA5E0000000000001"
PKG_GMA = "A11AD60B0000000000000001"
PKG_UMP = "A110A0D0B000000000000001"

PRODUCTS = [
    ("A11FA0000000000000000001", "A11FABF00000000000000001", PKG_FIREBASE, "FirebaseAnalytics"),
    ("A11FBC000000000000000001", "A11FBCBF0000000000000001", PKG_FIREBASE, "FirebaseRemoteConfig"),
    ("A11FCD000000000000000001", "A11FCDBF0000000000000001", PKG_FIREBASE, "FirebaseCrashlytics"),
    ("A11AD6100000000000000001", "A11AD61BF000000000000001", PKG_GMA, "GoogleMobileAds"),
    ("A110A0D10000000000000001", "A110A0D1BF00000000000001", PKG_UMP, "GoogleUserMessagingPlatform"),
]

for ids in [PKG_FIREBASE, PKG_GMA, PKG_UMP] + [p[0] for p in PRODUCTS] + [p[1] for p in PRODUCTS]:
    assert len(ids) == 24, f"{ids} len={len(ids)}"
    assert all(c in "0123456789ABCDEF" for c in ids), f"non-hex {ids}"

build_files = "".join(
    f"\t\t{bf} /* {pname} in Frameworks */ = {{isa = PBXBuildFile; productRef = {pid} /* {pname} */; }};\n"
    for pid, bf, _, pname in PRODUCTS
)
text = text.replace("/* End PBXBuildFile section */", build_files + "/* End PBXBuildFile section */", 1)

fw_marker = "\t\t84E6B60D29CD567E001723AE /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
fw_entries = "".join(f"\t\t\t\t{bf} /* {pname} in Frameworks */,\n" for _, bf, _, pname in PRODUCTS)
if "A11AD61BF000000000000001" not in text:
    if fw_marker not in text:
        raise SystemExit("Frameworks phase missing")
    text = text.replace(fw_marker, fw_marker + fw_entries, 1)

needle = "\t\t\tname = MMBrowser;\n\t\t\tproductName = MMBrowser;"
prod_deps = "".join(f"\t\t\t\t{pid} /* {pname} */,\n" for pid, _, _, pname in PRODUCTS)
replacement = (
    "\t\t\tname = MMBrowser;\n"
    "\t\t\tpackageProductDependencies = (\n"
    f"{prod_deps}"
    "\t\t\t);\n"
    "\t\t\tproductName = MMBrowser;"
)
if "packageProductDependencies" not in text:
    if needle not in text:
        raise SystemExit("target needle missing")
    text = text.replace(needle, replacement, 1)

proj_needle = "\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";"
proj_repl = (
    "\t\t\tpackageReferences = (\n"
    f"\t\t\t\t{PKG_FIREBASE} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */,\n"
    f"\t\t\t\t{PKG_GMA} /* XCRemoteSwiftPackageReference \"swift-package-manager-google-mobile-ads\" */,\n"
    f"\t\t\t\t{PKG_UMP} /* XCRemoteSwiftPackageReference \"swift-package-manager-google-user-messaging-platform\" */,\n"
    "\t\t\t);\n"
    "\t\t\tprojectDirPath = \"\";\n"
    "\t\t\tprojectRoot = \"\";"
)
if "packageReferences" not in text:
    if proj_needle not in text:
        raise SystemExit("project needle missing")
    text = text.replace(proj_needle, proj_repl, 1)

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
for pid, _, pkg, pname in PRODUCTS:
    package_section += f"""\t\t{pid} /* {pname} */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {pkg} /* XCRemoteSwiftPackageReference */;
			productName = {pname};
		}};
"""
package_section += "/* End XCSwiftPackageProductDependency section */\n"

anchor = "/* End XCConfigurationList section */\n\t};\n\trootObject = 84E6B60829CD567D001723AE /* Project object */;\n}\n"
if anchor not in text:
    raise SystemExit("anchor missing")
text = text.replace(
    anchor,
    "/* End XCConfigurationList section */\n" + package_section + "\t};\n\trootObject = 84E6B60829CD567D001723AE /* Project object */;\n}\n",
    1,
)

PBX.write_text(text)
print("SPM packages added")
