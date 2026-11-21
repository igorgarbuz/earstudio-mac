#!/usr/bin/env python3
"""Generate the iPhone app and test targets; shared serializer lives beside this file."""
import xml.etree.ElementTree as ET
import generate_project as g

ROOT = g.ROOT
PROJECT = ROOT / "EarStudioiOS.xcodeproj"
TARGETS = {
    "ios": ("EarStudioiOS", "EarStudio iOS.app"),
    "ios-tests": ("EarStudioIOSTests", "EarStudioIOSTests.xctest"),
    "ios-ui-tests": ("EarStudioIOSUITests", "EarStudioIOSUITests.xctest"),
}

def make_project():
    # Use source-root paths for the platform tree, without adding Mac files.
    group = g.folder_group(ROOT / "Apps/iOS")
    g.OBJECTS[group]["path"] = "Apps/iOS"
    tools = g.folder_group(ROOT / "Tools")
    package = g.add("ios-package", isa="XCLocalSwiftPackageReference", relativePath="Packages/EarStudioKit")
    product = g.add("ios-kit", isa="XCSwiftPackageProductDependency", productName="EarStudioKit")
    refs, targets = [], []
    for key, (name, filename) in TARGETS.items():
        is_app, is_ui = key == "ios", key == "ios-ui-tests"
        ref = g.add(key+"-product", isa="PBXFileReference", explicitFileType="wrapper.application" if is_app else "wrapper.cfbundle", path=filename, sourceTree="BUILT_PRODUCTS_DIR")
        refs.append(ref)
        folder = "Sources" if is_app else ("UITests" if is_ui else "Tests")
        files = sorted(p for p in g.FILE_REFS if p.startswith(f"Apps/iOS/{folder}/") and p.endswith(".swift"))
        phases = [g.phase(key+"-sources", "PBXSourcesBuildPhase", files), g.phase(key+"-frameworks", "PBXFrameworksBuildPhase", []), g.phase(key+"-resources", "PBXResourcesBuildPhase", ["Apps/iOS/Resources/Assets.xcassets"] if is_app else [])]
        if not is_ui:
            g.OBJECTS[phases[1]]["files"] = [g.add(key+"-link-kit", isa="PBXBuildFile", productRef=product)]
        deps = []
        if not is_app:
            proxy = g.add(key+"-proxy", isa="PBXContainerItemProxy", containerPortal=g.identifier("ios-project"), proxyType=1, remoteGlobalIDString=g.identifier("ios"), remoteInfo="EarStudioiOS")
            deps = [g.add(key+"-dep", isa="PBXTargetDependency", target=g.identifier("ios"), targetProxy=proxy)]
        config = "App" if is_app else ("UITests" if is_ui else "Tests")
        configs = g.configurations(key, lambda _, config=config: f"Apps/iOS/Configuration/{config}.xcconfig")
        targets.append(g.add(key, isa="PBXNativeTarget", buildConfigurationList=configs, buildPhases=phases, buildRules=[], dependencies=deps, packageProductDependencies=[] if is_ui else [product], name=name, productName=name, productReference=ref, productType="com.apple.product-type.application" if is_app else ("com.apple.product-type.bundle.ui-testing" if is_ui else "com.apple.product-type.bundle.unit-test")))
    products = g.add("ios-products", isa="PBXGroup", children=refs, name="Products", sourceTree="<group>")
    main = g.add("ios-main", isa="PBXGroup", children=[group, tools, products], sourceTree="<group>")
    configs = g.configurations("ios-project", lambda mode: f"Apps/iOS/Configuration/{mode}.xcconfig")
    project = g.add("ios-project", isa="PBXProject", attributes={"LastUpgradeCheck":"2630", "BuildIndependentTargetsInParallel":"YES", "TargetAttributes": {g.identifier(k): {"CreatedOnToolsVersion":"26.3", **({"TestTargetID":g.identifier("ios")} if k != "ios" else {})} for k in TARGETS}}, buildConfigurationList=configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en", "Base"], mainGroup=main, productRefGroup=products, projectDirPath="", projectRoot="", packageReferences=[package], targets=targets)
    PROJECT.mkdir(exist_ok=True)
    (PROJECT/"project.pbxproj").write_text("// !$*UTF8*$!\n" + g.render({"archiveVersion":1,"classes":{},"objectVersion":56,"objects":g.OBJECTS,"rootObject":project})+"\n")

def buildable(parent, key):
    name, filename = TARGETS[key]
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=g.identifier(key), BuildableName=filename, BlueprintName=name, ReferencedContainer="container:EarStudioiOS.xcodeproj")

def make_scheme():
    scheme=ET.Element("Scheme", LastUpgradeVersion="2630", version="1.3")
    action=ET.SubElement(scheme,"BuildAction",parallelizeBuildables="YES",buildImplicitDependencies="YES")
    entries=ET.SubElement(action,"BuildActionEntries")
    entry=ET.SubElement(entries,"BuildActionEntry",buildForTesting="YES",buildForRunning="YES",buildForProfiling="YES",buildForArchiving="YES",buildForAnalyzing="YES")
    buildable(entry,"ios")
    dbg={"selectedDebuggerIdentifier":"Xcode.DebuggerFoundation.Debugger.LLDB","selectedLauncherIdentifier":"Xcode.IDEFoundation.Launcher.LLDB"}
    tests=ET.SubElement(ET.SubElement(scheme,"TestAction",buildConfiguration="Debug",shouldUseLaunchSchemeArgsEnv="YES",**dbg),"Testables")
    for key in ("ios-tests","ios-ui-tests"):
        buildable(ET.SubElement(tests,"TestableReference",skipped="NO"),key)
    launch=ET.SubElement(scheme,"LaunchAction",buildConfiguration="Debug",launchStyle="0",useCustomWorkingDirectory="NO",ignoresPersistentStateOnLaunch="NO",debugDocumentVersioning="YES",allowLocationSimulation="YES",**dbg)
    buildable(ET.SubElement(launch,"BuildableProductRunnable",runnableDebuggingMode="0"),"ios")
    profile=ET.SubElement(scheme,"ProfileAction",buildConfiguration="Release",shouldUseLaunchSchemeArgsEnv="YES",useCustomWorkingDirectory="NO",debugDocumentVersioning="YES")
    buildable(ET.SubElement(profile,"BuildableProductRunnable",runnableDebuggingMode="0"),"ios")
    ET.SubElement(scheme,"AnalyzeAction",buildConfiguration="Debug")
    ET.SubElement(scheme,"ArchiveAction",buildConfiguration="Release",revealArchiveInOrganizer="YES")
    d=PROJECT/"xcshareddata/xcschemes";d.mkdir(parents=True,exist_ok=True)
    ET.indent(scheme,space="  ")
    ET.ElementTree(scheme).write(d/"EarStudioiOS.xcscheme",encoding="utf-8",xml_declaration=True)

if __name__ == "__main__":
    make_project(); make_scheme(); print(PROJECT)
