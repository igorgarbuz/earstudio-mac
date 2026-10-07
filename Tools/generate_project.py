#!/usr/bin/env python3
"""Generate the checked-in native Xcode project using Python's standard library.

Build settings live in Configuration/*.xcconfig. Xcode is the build system;
this helper is needed only after adding/removing files outside Xcode. Regeneration
replaces project/scheme edits but preserves source, xcconfig, and user settings.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "EarStudioCompanion.xcodeproj"
OBJECTS = {}
FILE_REFS = {}
FILE_TYPES = {
    ".swift": "sourcecode.swift", ".plist": "text.plist.xml",
    ".xcconfig": "text.xcconfig", ".md": "net.daringfireball.markdown",
    ".py": "text.script.python", ".sh": "text.script.sh",
    ".json": "text.json", ".xcassets": "folder.assetcatalog",
}


def identifier(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def add(key, **properties):
    object_id = identifier(key)
    OBJECTS[object_id] = properties
    return object_id


def render(value, indent=0):
    """Serialize the OpenStep property list accepted by Xcode and plutil."""
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append("\t" * (indent + 1) + f"{key} = {render(item, indent + 1)};")
        return "\n".join(lines) + "\n" + "\t" * indent + "}"
    if isinstance(value, list):
        if not value:
            return "()"
        return "(\n" + "".join("\t" * (indent + 1) + render(v, indent + 1) + ",\n" for v in value) + "\t" * indent + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)


def file_reference(path):
    relative = path.relative_to(ROOT).as_posix()
    ref = add(relative, isa="PBXFileReference", lastKnownFileType=FILE_TYPES.get(path.suffix, "text"),
              path=path.name, sourceTree="<group>")
    FILE_REFS[relative] = ref
    return ref


def folder_group(path):
    children = []
    for child in sorted(path.iterdir(), key=lambda p: (not p.is_dir(), p.name)):
        if child.name.startswith(".") or child.name == "__pycache__":
            continue
        if child.is_dir() and child.suffix != ".xcassets":
            children.append(folder_group(child))
        else:
            children.append(file_reference(child))
    return add("group-" + path.relative_to(ROOT).as_posix(), isa="PBXGroup", children=children,
               path=path.name, sourceTree="<group>")


def phase(name, kind, files):
    builds = [add("build-" + path, isa="PBXBuildFile", fileRef=FILE_REFS[path]) for path in files]
    return add(name, isa=kind, buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)


def configurations(key, file_for_mode):
    configs = []
    for mode in ("Debug", "Release"):
        configs.append(add(key + "-" + mode, isa="XCBuildConfiguration", name=mode, buildSettings={},
                           baseConfigurationReference=FILE_REFS[file_for_mode(mode)]))
    return add(key + "-config", isa="XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def make_project():
    groups = [folder_group(ROOT / name) for name in ("Sources", "Tests", "Resources", "Configuration", "Tools")]
    documents = [file_reference(ROOT / name) for name in ("README.md", "Package.swift")]
    app_product = add("app-product", isa="PBXFileReference", explicitFileType="wrapper.application",
                      path="EarStudio Companion.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = add("test-product", isa="PBXFileReference", explicitFileType="wrapper.cfbundle",
                       path="EarStudioCompanionTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("products", isa="PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
    main = add("main", isa="PBXGroup", children=groups + documents + [products], sourceTree="<group>")
    project_configs = configurations("project", lambda mode: f"Configuration/{mode}.xcconfig")
    app_configs = configurations("app", lambda _: "Configuration/App.xcconfig")
    test_configs = configurations("test", lambda _: "Configuration/Tests.xcconfig")
    source_files = sorted(p for p in FILE_REFS if p.startswith("Sources/") and p.endswith(".swift"))
    test_files = sorted(p for p in FILE_REFS if p.startswith("Tests/") and p.endswith(".swift"))
    app_phases = [phase("app-sources", "PBXSourcesBuildPhase", source_files),
                  phase("app-frameworks", "PBXFrameworksBuildPhase", []),
                  phase("app-resources", "PBXResourcesBuildPhase", ["Resources/Assets.xcassets"])]
    test_phases = [phase("test-sources", "PBXSourcesBuildPhase", test_files),
                   phase("test-frameworks", "PBXFrameworksBuildPhase", []),
                   phase("test-resources", "PBXResourcesBuildPhase", [])]
    proxy = add("proxy", isa="PBXContainerItemProxy", containerPortal=identifier("project"), proxyType=1,
                remoteGlobalIDString=identifier("app"), remoteInfo="EarStudioCompanion")
    dependency = add("test-dep", isa="PBXTargetDependency", target=identifier("app"), targetProxy=proxy)
    app = add("app", isa="PBXNativeTarget", buildConfigurationList=app_configs, buildPhases=app_phases,
              buildRules=[], dependencies=[], name="EarStudioCompanion", productName="EarStudio Companion",
              productReference=app_product, productType="com.apple.product-type.application")
    test = add("test", isa="PBXNativeTarget", buildConfigurationList=test_configs, buildPhases=test_phases,
               buildRules=[], dependencies=[dependency], name="EarStudioCompanionTests",
               productName="EarStudioCompanionTests", productReference=test_product,
               productType="com.apple.product-type.bundle.unit-test")
    project = add("project", isa="PBXProject", attributes={"LastUpgradeCheck": "2630", "BuildIndependentTargetsInParallel": "YES",
                  "TargetAttributes": {app: {"CreatedOnToolsVersion": "26.3"}, test: {"CreatedOnToolsVersion": "26.3", "TestTargetID": app}}},
                  buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en",
                  knownRegions=["en", "Base"], mainGroup=main, productRefGroup=products,
                  projectDirPath="", projectRoot="", targets=[app, test])
    PROJECT.mkdir(exist_ok=True)
    content = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": OBJECTS, "rootObject": project}
    (PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(content) + "\n")


def buildable(parent, target):
    app = target == "app"
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=identifier(target),
                  BuildableName="EarStudio Companion.app" if app else "EarStudioCompanionTests.xctest",
                  BlueprintName="EarStudioCompanion" if app else "EarStudioCompanionTests",
                  ReferencedContainer="container:EarStudioCompanion.xcodeproj")


def make_scheme():
    scheme = ET.Element("Scheme", LastUpgradeVersion="2630", version="1.3")
    action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(action, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES",
                          buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    buildable(entry, "app")
    debugger = {"selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
                "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB"}
    test_action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", shouldUseLaunchSchemeArgsEnv="YES", **debugger)
    testable = ET.SubElement(ET.SubElement(test_action, "Testables"), "TestableReference", skipped="NO")
    buildable(testable, "test")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", launchStyle="0",
                           useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO",
                           debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES", **debugger)
    buildable(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "app")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
                            savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    buildable(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "app")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    directory = PROJECT / "xcshareddata/xcschemes"
    directory.mkdir(parents=True, exist_ok=True)
    ET.indent(scheme, space="  ")
    ET.ElementTree(scheme).write(directory / "EarStudioCompanion.xcscheme", encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    make_project()
    make_scheme()
    print(PROJECT)
