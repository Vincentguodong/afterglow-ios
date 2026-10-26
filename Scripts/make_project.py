#!/usr/bin/env python3
"""Generate the checked-in Xcode project deterministically; no third-party tools."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def add(key, body):
    objects[ident(key)] = body
    return ident(key)
def quote(s): return json.dumps(str(s), ensure_ascii=False)
def array(values): return '(' + ', '.join(values) + ', )' if values else '()'
def settings(values): return '{ ' + ' '.join(f'{k} = {quote(v)};' for k, v in values.items()) + ' }'

app_sources = sorted((ROOT/'Afterglow').glob('*.swift'))
test_sources = sorted((ROOT/'AfterglowTests').glob('*.swift'))
app_refs, source_builds, resource_builds, test_refs, test_builds = [], [], [], [], []
for file in app_sources + test_sources:
    ref = add(str(file.relative_to(ROOT)), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(file.name)}; sourceTree = "<group>";')
    build = add('build:'+str(file.relative_to(ROOT)), f'isa = PBXBuildFile; fileRef = {ref};')
    if file.parent.name == 'Afterglow': app_refs.append(ref); source_builds.append(build)
    else: test_refs.append(ref); test_builds.append(build)
for name, kind in [('Assets.xcassets', 'folder.assetcatalog'), ('PrivacyInfo.xcprivacy','text.xml'), ('Info.plist','text.plist.xml')]:
    ref = add(name, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {name}; sourceTree = "<group>";')
    app_refs.append(ref)
    if name != 'Info.plist': resource_builds.append(add('build:'+name, f'isa = PBXBuildFile; fileRef = {ref};'))
app_product = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Afterglow.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = AfterglowTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
app_group = add('app-group', f'isa = PBXGroup; children = {array(app_refs)}; path = Afterglow; sourceTree = "<group>";')
test_group = add('test-group', f'isa = PBXGroup; children = {array(test_refs)}; path = AfterglowTests; sourceTree = "<group>";')
products = add('products', f'isa = PBXGroup; children = {array([app_product,test_product])}; name = Products; sourceTree = "<group>";')
group = add('root-group', f'isa = PBXGroup; children = {array([app_group,test_group,products])}; sourceTree = "<group>";')
def phase(name, kind, files):
    return add(name, f'isa = {kind}; buildActionMask = 2147483647; files = {array(files)}; runOnlyForDeploymentPostprocessing = 0;')
app_phases = [phase('app-sources', 'PBXSourcesBuildPhase', source_builds),phase('app-frameworks','PBXFrameworksBuildPhase',[]),phase('app-resources','PBXResourcesBuildPhase',resource_builds)]
test_phases = [phase('test-sources','PBXSourcesBuildPhase',test_builds),phase('test-frameworks','PBXFrameworksBuildPhase',[]),phase('test-resources','PBXResourcesBuildPhase',[])]
base = {'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
app = {'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'2','MARKETING_VERSION':'1.1.0','PRODUCT_BUNDLE_IDENTIFIER':'com.example.afterglow','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Afterglow/Info.plist','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SWIFT_EMIT_LOC_STRINGS':'YES'}
test = {'CODE_SIGN_STYLE':'Automatic','PRODUCT_BUNDLE_IDENTIFIER':'com.example.afterglow.tests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'1','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Afterglow.app/Afterglow','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks'}
def configurations(name, values):
    ids=[]
    for configuration in ['Debug','Release']:
        v = dict(values)
        if name == 'project':
            v.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if configuration=='Debug' else 'dwarf-with-dsym'})
            if configuration=='Debug': v.update({'ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)'})
        ids.append(add(name+configuration, f'isa = XCBuildConfiguration; buildSettings = {settings(v)}; name = {configuration};'))
    return add(name+'configs', f'isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project_configs = configurations('project',base)
app_configs = configurations('app',app)
test_configs = configurations('test',test)
app_target = add('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {array(app_phases)}; buildRules = (); dependencies = (); name = Afterglow; productName = Afterglow; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = add('proxy',f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = Afterglow;')
dependency = add('dependency',f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
test_target = add('test-target',f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {array(test_phases)}; buildRules = (); dependencies = {array([dependency])}; name = AfterglowTests; productName = AfterglowTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
project = add('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{ {app_target} = {{ CreatedOnToolsVersion = 26.0; }}; {test_target} = {{ CreatedOnToolsVersion = 26.0; TestTargetID = {app_target}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app_target,test_target])};')
out = '// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
out += '\n'.join(f'  {key} = {{ {value} }};' for key,value in objects.items())
out += '\n };\n rootObject = '+project+';\n}\n'
(ROOT/'Afterglow.xcodeproj/project.pbxproj').write_text(out)
def ref(target, name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Afterglow.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app_target,'Afterglow.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test_target,'AfterglowTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target,'Afterglow.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target,'Afterglow.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(ROOT/'Afterglow.xcodeproj/xcshareddata/xcschemes/Afterglow.xcscheme').write_text(scheme)
print(f'Generated {len(app_sources)} app sources and {len(test_sources)} test source in Afterglow.xcodeproj')
