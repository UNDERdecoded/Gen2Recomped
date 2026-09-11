-- VR: the OpenXR binding -- instance, session, swapchains and the frame
-- loop, spoken to the runtime directly over LuaJIT's FFI so the parent
-- app never has to know VR exists.
--
-- The loader (assets/vr/openxr_loader.dll, the Khronos-shipped x64 build)
-- finds whatever runtime the player has -- SteamVR, the Oculus runtime,
-- WMR -- through the OS's normal OpenXR plumbing. This module drives the
-- exact ceremony the spec requires and nothing else:
--
--   instance (with XR_KHR_opengl_enable) -> system (an HMD) ->
--   graphics-requirements call (mandatory before the session) ->
--   session bound to LOVE's own GL context (the HDC/HGLRC the window is
--   already rendering with, via VRGL) -> LOCAL reference space ->
--   one swapchain per eye at the runtime's recommended size, plus one
--   more for the UI quad -> per frame: poll events, wait/begin, locate
--   views, hand textures out to be blitted into, end with layers.
--
-- Everything FFI-shaped lives HERE: cdata never leaks to callers. Poses
-- and fovs come out as plain Lua tables (VRRig's shape); textures come
-- out as GL ids for VRGL. Every entry point is pcall-guarded and failure
-- is a status string, never an error -- a machine with no runtime, no
-- headset or no GL interop reports why and the mod plays flat.
--
-- What this deliberately does NOT do (v1): XR input (play with the pad,
-- keyboard or mouse -- they all still work with a headset on), depth
-- layers, and Linux/Android graphics bindings (the cdef binds Win32 GL,
-- the one platform LOVE + this loader serve together).

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local VRGL = V.require("VRGL")

local VRXR = {}

local ffi = nil
local xr = nil                  -- the loader library
local C = nil                   -- ffi namespace shortcut

-- ------- state
local status = "not started"
local instance, systemId, session, space = nil, nil, nil, nil
local views = nil               -- XrViewConfigurationView[2] (sizes)
local eyes = {}                 -- per eye: { swapchain, images={texids}, w, h }
local quad = nil                -- { swapchain, images, w, h }
local sessionState = 0
local running = false           -- xrBeginSession happened
local viewsBuf = nil            -- XrView[2], refreshed per locate
local lastViews = nil           -- lua copies of the located views

-- ------- constants (openxr.h, core 1.0 + XR_KHR_opengl_enable)
local XR = {
  TYPE_INSTANCE_CREATE_INFO = 3,
  TYPE_SYSTEM_GET_INFO = 4,
  TYPE_VIEW_LOCATE_INFO = 6,
  TYPE_VIEW = 7,
  TYPE_SESSION_CREATE_INFO = 8,
  TYPE_SWAPCHAIN_CREATE_INFO = 9,
  TYPE_SESSION_BEGIN_INFO = 10,
  TYPE_VIEW_STATE = 11,
  TYPE_FRAME_END_INFO = 12,
  TYPE_EVENT_DATA_BUFFER = 16,
  TYPE_EVENT_DATA_SESSION_STATE_CHANGED = 18,
  TYPE_FRAME_WAIT_INFO = 33,
  TYPE_COMPOSITION_LAYER_PROJECTION = 35,
  TYPE_COMPOSITION_LAYER_QUAD = 36,
  TYPE_REFERENCE_SPACE_CREATE_INFO = 37,
  TYPE_VIEW_CONFIGURATION_VIEW = 41,
  TYPE_FRAME_STATE = 44,
  TYPE_FRAME_BEGIN_INFO = 46,
  TYPE_COMPOSITION_LAYER_PROJECTION_VIEW = 48,
  TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO = 55,
  TYPE_SWAPCHAIN_IMAGE_WAIT_INFO = 56,
  TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO = 57,
  TYPE_ACTION_STATE_BOOLEAN = 23,
  TYPE_ACTION_STATE_FLOAT = 24,
  TYPE_ACTION_STATE_VECTOR2F = 25,
  TYPE_ACTION_SET_CREATE_INFO = 28,
  TYPE_ACTION_CREATE_INFO = 29,
  TYPE_ACTION_SPACE_CREATE_INFO = 38,
  TYPE_SPACE_LOCATION = 42,
  TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING = 51,
  TYPE_ACTION_STATE_GET_INFO = 58,
  TYPE_SESSION_ACTION_SETS_ATTACH_INFO = 60,
  TYPE_ACTIONS_SYNC_INFO = 61,
  TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR = 1000023000,
  TYPE_SWAPCHAIN_IMAGE_OPENGL_KHR = 1000023004,
  TYPE_GRAPHICS_REQUIREMENTS_OPENGL_KHR = 1000023005,

  ACTION_TYPE_BOOLEAN = 1,
  ACTION_TYPE_FLOAT = 2,
  ACTION_TYPE_VECTOR2F = 3,
  ACTION_TYPE_POSE = 4,

  SPACE_LOCATION_POSITION_VALID_BIT = 0x2,

  FORM_FACTOR_HEAD_MOUNTED_DISPLAY = 1,
  VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO = 2,
  REFERENCE_SPACE_TYPE_LOCAL = 2,
  ENVIRONMENT_BLEND_MODE_OPAQUE = 1,
  EYE_VISIBILITY_BOTH = 0,

  SESSION_STATE_READY = 2,
  SESSION_STATE_STOPPING = 6,
  SESSION_STATE_EXITING = 8,
  SESSION_STATE_LOSS_PENDING = 7,

  SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT = 0x1,
  SWAPCHAIN_USAGE_TRANSFER_DST_BIT = 0x10,
  SWAPCHAIN_USAGE_SAMPLED_BIT = 0x20,

  INFINITE_DURATION = 0x7fffffffffffffffLL,
  API_VERSION_1_0 = 0x0001000000000000ULL,   -- XR_MAKE_VERSION(1, 0, 0)

  GL_RGBA8 = 0x8058,
  GL_SRGB8_ALPHA8 = 0x8C43,
}
VRXR.XR = XR

-- the failures a player can actually act on, by name (values verified
-- against openxr.h -- the probe once printed a bare number because two of
-- these were guessed wrong)
local RESULT_NAMES = {
  [0] = "XR_SUCCESS",
  [-2] = "XR_ERROR_RUNTIME_FAILURE",
  [-4] = "XR_ERROR_API_VERSION_UNSUPPORTED",
  [-6] = "XR_ERROR_INITIALIZATION_FAILED",
  [-9] = "XR_ERROR_EXTENSION_NOT_PRESENT (runtime has no OpenGL support)",
  [-26] = "XR_ERROR_SWAPCHAIN_FORMAT_UNSUPPORTED",
  [-34] = "XR_ERROR_FORM_FACTOR_UNSUPPORTED",
  [-35] = "XR_ERROR_FORM_FACTOR_UNAVAILABLE"
          .. " (headset not connected or not ready)",
  [-38] = "XR_ERROR_GRAPHICS_DEVICE_INVALID",
  [-50] = "XR_ERROR_GRAPHICS_REQUIREMENTS_CALL_MISSING",
  [-51] = "XR_ERROR_RUNTIME_UNAVAILABLE (no OpenXR runtime installed)",
}
local function resultName(r)
  return RESULT_NAMES[tonumber(r)] or ("XrResult " .. tonumber(r))
end

local CDEF = [[
typedef uint64_t XrVersion; typedef uint64_t XrFlags64;
typedef uint64_t XrSystemId; typedef int64_t XrTime;
typedef int64_t XrDuration; typedef uint32_t XrBool32;
typedef int32_t XrResult; typedef int32_t XrStructureType;
typedef struct XrInstance_T* XrInstance;
typedef struct XrSession_T* XrSession;
typedef struct XrSpace_T* XrSpace;
typedef struct XrSwapchain_T* XrSwapchain;

typedef struct XrApplicationInfo {
  char applicationName[128]; uint32_t applicationVersion;
  char engineName[128]; uint32_t engineVersion; XrVersion apiVersion;
} XrApplicationInfo;
typedef struct XrInstanceCreateInfo {
  XrStructureType type; const void* next; XrFlags64 createFlags;
  XrApplicationInfo applicationInfo;
  uint32_t enabledApiLayerCount; const char* const* enabledApiLayerNames;
  uint32_t enabledExtensionCount; const char* const* enabledExtensionNames;
} XrInstanceCreateInfo;
typedef struct XrSystemGetInfo {
  XrStructureType type; const void* next; int32_t formFactor;
} XrSystemGetInfo;
typedef struct XrGraphicsRequirementsOpenGLKHR {
  XrStructureType type; void* next;
  XrVersion minApiVersionSupported; XrVersion maxApiVersionSupported;
} XrGraphicsRequirementsOpenGLKHR;
typedef struct XrGraphicsBindingOpenGLWin32KHR {
  XrStructureType type; const void* next; void* hDC; void* hGLRC;
} XrGraphicsBindingOpenGLWin32KHR;
typedef struct XrSessionCreateInfo {
  XrStructureType type; const void* next; XrFlags64 createFlags;
  XrSystemId systemId;
} XrSessionCreateInfo;
typedef struct XrVector3f { float x, y, z; } XrVector3f;
typedef struct XrQuaternionf { float x, y, z, w; } XrQuaternionf;
typedef struct XrPosef { XrQuaternionf orientation; XrVector3f position; } XrPosef;
typedef struct XrReferenceSpaceCreateInfo {
  XrStructureType type; const void* next; int32_t referenceSpaceType;
  XrPosef poseInReferenceSpace;
} XrReferenceSpaceCreateInfo;
typedef struct XrViewConfigurationView {
  XrStructureType type; void* next;
  uint32_t recommendedImageRectWidth; uint32_t maxImageRectWidth;
  uint32_t recommendedImageRectHeight; uint32_t maxImageRectHeight;
  uint32_t recommendedSwapchainSampleCount; uint32_t maxSwapchainSampleCount;
} XrViewConfigurationView;
typedef struct XrSwapchainCreateInfo {
  XrStructureType type; const void* next; XrFlags64 createFlags;
  XrFlags64 usageFlags; int64_t format; uint32_t sampleCount;
  uint32_t width; uint32_t height; uint32_t faceCount; uint32_t arraySize;
  uint32_t mipCount;
} XrSwapchainCreateInfo;
typedef struct XrSwapchainImageOpenGLKHR {
  XrStructureType type; void* next; uint32_t image;
} XrSwapchainImageOpenGLKHR;
typedef struct XrEventDataBuffer {
  XrStructureType type; const void* next; uint8_t varying[4000];
} XrEventDataBuffer;
typedef struct XrEventDataSessionStateChanged {
  XrStructureType type; const void* next; XrSession session;
  int32_t state; XrTime time;
} XrEventDataSessionStateChanged;
typedef struct XrFrameWaitInfo { XrStructureType type; const void* next; } XrFrameWaitInfo;
typedef struct XrFrameState {
  XrStructureType type; void* next; XrTime predictedDisplayTime;
  XrDuration predictedDisplayPeriod; XrBool32 shouldRender;
} XrFrameState;
typedef struct XrFrameBeginInfo { XrStructureType type; const void* next; } XrFrameBeginInfo;
typedef struct XrViewLocateInfo {
  XrStructureType type; const void* next; int32_t viewConfigurationType;
  XrTime displayTime; XrSpace space;
} XrViewLocateInfo;
typedef struct XrViewState { XrStructureType type; void* next; XrFlags64 viewStateFlags; } XrViewState;
typedef struct XrFovf { float angleLeft, angleRight, angleUp, angleDown; } XrFovf;
typedef struct XrView { XrStructureType type; void* next; XrPosef pose; XrFovf fov; } XrView;
typedef struct XrSwapchainImageAcquireInfo { XrStructureType type; const void* next; } XrSwapchainImageAcquireInfo;
typedef struct XrSwapchainImageWaitInfo {
  XrStructureType type; const void* next; XrDuration timeout;
} XrSwapchainImageWaitInfo;
typedef struct XrSwapchainImageReleaseInfo { XrStructureType type; const void* next; } XrSwapchainImageReleaseInfo;
typedef struct XrOffset2Di { int32_t x, y; } XrOffset2Di;
typedef struct XrExtent2Di { int32_t width, height; } XrExtent2Di;
typedef struct XrRect2Di { XrOffset2Di offset; XrExtent2Di extent; } XrRect2Di;
typedef struct XrSwapchainSubImage {
  XrSwapchain swapchain; XrRect2Di imageRect; uint32_t imageArrayIndex;
} XrSwapchainSubImage;
typedef struct XrCompositionLayerProjectionView {
  XrStructureType type; const void* next; XrPosef pose; XrFovf fov;
  XrSwapchainSubImage subImage;
} XrCompositionLayerProjectionView;
typedef struct XrCompositionLayerProjection {
  XrStructureType type; const void* next; XrFlags64 layerFlags;
  XrSpace space; uint32_t viewCount;
  const XrCompositionLayerProjectionView* views;
} XrCompositionLayerProjection;
typedef struct XrExtent2Df { float width, height; } XrExtent2Df;
typedef struct XrCompositionLayerQuad {
  XrStructureType type; const void* next; XrFlags64 layerFlags;
  XrSpace space; int32_t eyeVisibility; XrSwapchainSubImage subImage;
  XrPosef pose; XrExtent2Df size;
} XrCompositionLayerQuad;
typedef struct XrSessionBeginInfo {
  XrStructureType type; const void* next; int32_t primaryViewConfigurationType;
} XrSessionBeginInfo;
typedef struct XrFrameEndInfo {
  XrStructureType type; const void* next; XrTime displayTime;
  int32_t environmentBlendMode; uint32_t layerCount;
  const void* const* layers;
} XrFrameEndInfo;

XrResult xrCreateInstance(const XrInstanceCreateInfo*, XrInstance*);
XrResult xrDestroyInstance(XrInstance);
XrResult xrGetSystem(XrInstance, const XrSystemGetInfo*, XrSystemId*);
XrResult xrGetInstanceProcAddr(XrInstance, const char*, void**);
XrResult xrCreateSession(XrInstance, const XrSessionCreateInfo*, XrSession*);
XrResult xrDestroySession(XrSession);
XrResult xrCreateReferenceSpace(XrSession, const XrReferenceSpaceCreateInfo*, XrSpace*);
XrResult xrEnumerateViewConfigurationViews(XrInstance, XrSystemId, int32_t,
    uint32_t, uint32_t*, XrViewConfigurationView*);
XrResult xrEnumerateSwapchainFormats(XrSession, uint32_t, uint32_t*, int64_t*);
XrResult xrCreateSwapchain(XrSession, const XrSwapchainCreateInfo*, XrSwapchain*);
XrResult xrEnumerateSwapchainImages(XrSwapchain, uint32_t, uint32_t*, void*);
XrResult xrAcquireSwapchainImage(XrSwapchain, const XrSwapchainImageAcquireInfo*, uint32_t*);
XrResult xrWaitSwapchainImage(XrSwapchain, const XrSwapchainImageWaitInfo*);
XrResult xrReleaseSwapchainImage(XrSwapchain, const XrSwapchainImageReleaseInfo*);
XrResult xrBeginSession(XrSession, const XrSessionBeginInfo*);
XrResult xrEndSession(XrSession);
XrResult xrPollEvent(XrInstance, XrEventDataBuffer*);
XrResult xrWaitFrame(XrSession, const XrFrameWaitInfo*, XrFrameState*);
XrResult xrBeginFrame(XrSession, const XrFrameBeginInfo*);
XrResult xrLocateViews(XrSession, const XrViewLocateInfo*, XrViewState*,
    uint32_t, uint32_t*, XrView*);
XrResult xrEndFrame(XrSession, const XrFrameEndInfo*);
typedef XrResult (__stdcall *PFN_xrGetOpenGLGraphicsRequirementsKHR)(
    XrInstance, XrSystemId, XrGraphicsRequirementsOpenGLKHR*);

typedef struct XrActionSet_T* XrActionSet;
typedef struct XrAction_T* XrAction;
typedef uint64_t XrPath;
typedef struct XrActionSetCreateInfo {
  XrStructureType type; const void* next; char actionSetName[64];
  char localizedActionSetName[128]; uint32_t priority;
} XrActionSetCreateInfo;
typedef struct XrActionCreateInfo {
  XrStructureType type; const void* next; char actionName[64];
  int32_t actionType; uint32_t countSubactionPaths;
  const XrPath* subactionPaths; char localizedActionName[128];
} XrActionCreateInfo;
typedef struct XrActionSuggestedBinding {
  XrAction action; XrPath binding;
} XrActionSuggestedBinding;
typedef struct XrInteractionProfileSuggestedBinding {
  XrStructureType type; const void* next; XrPath interactionProfile;
  uint32_t countSuggestedBindings;
  const XrActionSuggestedBinding* suggestedBindings;
} XrInteractionProfileSuggestedBinding;
typedef struct XrSessionActionSetsAttachInfo {
  XrStructureType type; const void* next; uint32_t countActionSets;
  const XrActionSet* actionSets;
} XrSessionActionSetsAttachInfo;
typedef struct XrActiveActionSet {
  XrActionSet actionSet; XrPath subactionPath;
} XrActiveActionSet;
typedef struct XrActionsSyncInfo {
  XrStructureType type; const void* next; uint32_t countActiveActionSets;
  const XrActiveActionSet* activeActionSets;
} XrActionsSyncInfo;
typedef struct XrActionStateGetInfo {
  XrStructureType type; const void* next; XrAction action;
  XrPath subactionPath;
} XrActionStateGetInfo;
typedef struct XrActionStateBoolean {
  XrStructureType type; void* next; XrBool32 currentState;
  XrBool32 changedSinceLastSync; XrTime lastChangeTime; XrBool32 isActive;
} XrActionStateBoolean;
typedef struct XrActionStateFloat {
  XrStructureType type; void* next; float currentState;
  XrBool32 changedSinceLastSync; XrTime lastChangeTime; XrBool32 isActive;
} XrActionStateFloat;
typedef struct XrVector2f { float x, y; } XrVector2f;
typedef struct XrActionStateVector2f {
  XrStructureType type; void* next; XrVector2f currentState;
  XrBool32 changedSinceLastSync; XrTime lastChangeTime; XrBool32 isActive;
} XrActionStateVector2f;
typedef struct XrActionSpaceCreateInfo {
  XrStructureType type; const void* next; XrAction action;
  XrPath subactionPath; XrPosef poseInActionSpace;
} XrActionSpaceCreateInfo;
typedef struct XrSpaceLocation {
  XrStructureType type; void* next; XrFlags64 locationFlags; XrPosef pose;
} XrSpaceLocation;
XrResult xrStringToPath(XrInstance, const char*, XrPath*);
XrResult xrCreateActionSet(XrInstance, const XrActionSetCreateInfo*, XrActionSet*);
XrResult xrCreateAction(XrActionSet, const XrActionCreateInfo*, XrAction*);
XrResult xrSuggestInteractionProfileBindings(XrInstance,
    const XrInteractionProfileSuggestedBinding*);
XrResult xrAttachSessionActionSets(XrSession, const XrSessionActionSetsAttachInfo*);
XrResult xrSyncActions(XrSession, const XrActionsSyncInfo*);
XrResult xrGetActionStateBoolean(XrSession, const XrActionStateGetInfo*,
    XrActionStateBoolean*);
XrResult xrGetActionStateFloat(XrSession, const XrActionStateGetInfo*,
    XrActionStateFloat*);
XrResult xrGetActionStateVector2f(XrSession, const XrActionStateGetInfo*,
    XrActionStateVector2f*);
XrResult xrCreateActionSpace(XrSession, const XrActionSpaceCreateInfo*, XrSpace*);
XrResult xrLocateSpace(XrSpace, XrSpace, XrTime, XrSpaceLocation*);
]]

-- ------- plumbing

local function fail(what, r)
  status = what .. ": " .. (r and resultName(r) or "error")
  return nil
end

local function check(r, what)
  if tonumber(r) ~= 0 then
    error(what .. " failed: " .. resultName(r), 0)
  end
end

-- Where the loader DLL might really be on disk. mod.path is
-- PHYSFS-relative; ffi.load needs an OS path. The dev tree answers to
-- the working directory or the source directory -- but an INSTALLED
-- release is neither: importing a mod there lands it in the game's SAVE
-- DIRECTORY, so the mount that actually holds the mod
-- (getRealDirectory) and the save directory itself are both tried too.
local DLL_REL = "assets/vr/openxr_loader.dll"

local function loaderCandidates()
  local rel = (V.path or "mods/DramaticShapeVoxelMod") .. "/" .. DLL_REL
  local list = { rel }
  local okR, real = pcall(function()
    return love.filesystem.getRealDirectory(rel)
  end)
  if okR and type(real) == "string" then
    list[#list + 1] = real .. "/" .. rel
  end
  local ok, src = pcall(function() return love.filesystem.getSource() end)
  if ok and type(src) == "string" then list[#list + 1] = src .. "/" .. rel end
  local okS, save = pcall(function()
    return love.filesystem.getSaveDirectory()
  end)
  if okS and type(save) == "string" then list[#list + 1] = save .. "/" .. rel end
  list[#list + 1] = "openxr_loader"   -- last resort: the system search path
  return list
end

VRXR._loaderCandidates = loaderCandidates   -- named for the suite

-- The escape hatch for a mod imported as an ARCHIVE (or mounted anywhere
-- else ffi.load cannot see): copy the DLL out of the mount into the save
-- directory -- a real folder on every platform -- and load it from
-- there. Written once and reused; rewritten only if the size changed (a
-- mod update shipping a new loader).
local EXTRACTED = "dramatic_shape_openxr_loader.dll"

local function extractLoader()
  local okB, bytes = pcall(function()
    return V.mod and V.mod.read and V.mod:read(DLL_REL)
  end)
  if not (okB and type(bytes) == "string" and #bytes > 0) then return nil end
  local ok, path = pcall(function()
    local have = love.filesystem.getInfo and love.filesystem.getInfo(EXTRACTED)
    if not (have and have.size == #bytes) then
      if not love.filesystem.write(EXTRACTED, bytes) then return nil end
    end
    local save = love.filesystem.getSaveDirectory()
    if type(save) ~= "string" then return nil end
    return save .. "/" .. EXTRACTED
  end)
  return ok and path or nil
end

local function loadLoader()
  ffi = require("ffi")
  pcall(ffi.cdef, CDEF)
  C = ffi
  local errs = {}
  for _, path in ipairs(loaderCandidates()) do
    local ok, lib = pcall(ffi.load, path)
    if ok then return lib end
    errs[#errs + 1] = tostring(lib)
  end
  -- nothing loadable in place: extract a copy to the save directory
  local extracted = extractLoader()
  if extracted then
    local ok, lib = pcall(ffi.load, extracted)
    if ok then return lib end
    errs[#errs + 1] = tostring(lib)
  end
  error("openxr_loader.dll not loadable from the mod, the save directory "
        .. "or the system: " .. table.concat(errs, " | "), 0)
end

local function makeSwapchain(w, h, format)
  local info = ffi.new("XrSwapchainCreateInfo")
  info.type = XR.TYPE_SWAPCHAIN_CREATE_INFO
  info.usageFlags = XR.SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT
                    + XR.SWAPCHAIN_USAGE_TRANSFER_DST_BIT
                    + XR.SWAPCHAIN_USAGE_SAMPLED_BIT
  info.format = format
  info.sampleCount = 1
  info.width, info.height = w, h
  info.faceCount, info.arraySize, info.mipCount = 1, 1, 1
  local out = ffi.new("XrSwapchain[1]")
  check(xr.xrCreateSwapchain(session, info, out), "xrCreateSwapchain")
  local chain = out[0]
  local count = ffi.new("uint32_t[1]")
  check(xr.xrEnumerateSwapchainImages(chain, 0, count, nil),
        "xrEnumerateSwapchainImages(count)")
  local imgs = ffi.new("XrSwapchainImageOpenGLKHR[?]", count[0])
  for i = 0, count[0] - 1 do
    imgs[i].type = XR.TYPE_SWAPCHAIN_IMAGE_OPENGL_KHR
  end
  check(xr.xrEnumerateSwapchainImages(chain, count[0], count, imgs),
        "xrEnumerateSwapchainImages")
  local texids = {}
  for i = 0, count[0] - 1 do texids[i + 1] = tonumber(imgs[i].image) end
  return { swapchain = chain, images = texids, w = w, h = h }
end

-- The swapchain format: LOVE's canvases are plain RGBA8, so ask for that
-- and take sRGB8 only when it is all the runtime offers (colours come out
-- slightly lifted there; documented rather than corrected in v1).
local function pickFormat()
  local count = ffi.new("uint32_t[1]")
  check(xr.xrEnumerateSwapchainFormats(session, 0, count, nil),
        "xrEnumerateSwapchainFormats(count)")
  local fmts = ffi.new("int64_t[?]", count[0])
  check(xr.xrEnumerateSwapchainFormats(session, count[0], count, fmts),
        "xrEnumerateSwapchainFormats")
  local has = {}
  for i = 0, count[0] - 1 do has[tonumber(fmts[i])] = true end
  if has[XR.GL_RGBA8] then return XR.GL_RGBA8 end
  if has[XR.GL_SRGB8_ALPHA8] then return XR.GL_SRGB8_ALPHA8 end
  return tonumber(fmts[0])
end

-- ------- input: one action set, the mod's fixed verbs
--
-- OpenXR input is semantic: the app declares ACTIONS (move, A, grip...),
-- suggests where they live on the controllers it knows, and the runtime
-- owns the actual binding (and lets the player rebind in its own UI).
-- The suggestions below cover Touch, Index and WMR sticks-and-buttons
-- style, plus the khr/simple fallback every runtime accepts. Input is
-- OPTIONAL: a runtime that refuses any of this leaves `input` nil and VR
-- stays view-only with the desk's own controls.

local input = nil       -- { set, A = {name->XrAction}, spaces, active }

local function toPath(str)
  local out = ffi.new("XrPath[1]")
  check(xr.xrStringToPath(instance, str, out), "xrStringToPath " .. str)
  return out[0]
end

local function makeAction(set, name, atype, localized)
  local info = ffi.new("XrActionCreateInfo")
  info.type = XR.TYPE_ACTION_CREATE_INFO
  ffi.copy(info.actionName, name)
  info.actionType = atype
  ffi.copy(info.localizedActionName, localized)
  local out = ffi.new("XrAction[1]")
  check(xr.xrCreateAction(set, info, out), "xrCreateAction " .. name)
  return out[0]
end

local function setupInput()
  local sci = ffi.new("XrActionSetCreateInfo")
  sci.type = XR.TYPE_ACTION_SET_CREATE_INFO
  ffi.copy(sci.actionSetName, "gameplay")
  ffi.copy(sci.localizedActionSetName, "Gameplay")
  local setOut = ffi.new("XrActionSet[1]")
  check(xr.xrCreateActionSet(instance, sci, setOut), "xrCreateActionSet")
  local set = setOut[0]

  local A = {
    move = makeAction(set, "move", XR.ACTION_TYPE_VECTOR2F, "Move"),
    look = makeAction(set, "look", XR.ACTION_TYPE_VECTOR2F, "Zoom / Look"),
    a = makeAction(set, "btn_a", XR.ACTION_TYPE_BOOLEAN, "A"),
    b = makeAction(set, "btn_b", XR.ACTION_TYPE_BOOLEAN, "B"),
    start = makeAction(set, "btn_start", XR.ACTION_TYPE_BOOLEAN, "Start"),
    toggle = makeAction(set, "viewtoggle", XR.ACTION_TYPE_BOOLEAN,
                        "First / Third Person"),
    gripl = makeAction(set, "grip_l", XR.ACTION_TYPE_FLOAT, "Left Grip"),
    gripr = makeAction(set, "grip_r", XR.ACTION_TYPE_FLOAT, "Right Grip"),
    handl = makeAction(set, "hand_l", XR.ACTION_TYPE_POSE, "Left Hand"),
    handr = makeAction(set, "hand_r", XR.ACTION_TYPE_POSE, "Right Hand"),
    -- HORDE MODE's two. `fire` is bound ALONGSIDE start on the right
    -- trigger rather than instead of it: bindings are suggested once,
    -- before the session attaches its action sets, so they cannot be
    -- swapped when the mode starts -- and OpenXR is happy for two actions
    -- to share an input. Outside the mode nothing reads `fire`, so the
    -- trigger is START exactly as it always was; inside it, lib/VR reads
    -- `fire` and drops START on the floor (there is no pausing anyway).
    -- `aimr` is the pose a runtime defines as "where the user is
    -- pointing", which is what a gun wants -- the grip pose points along
    -- the controller's own body, which is a wrist, not a barrel.
    fire = makeAction(set, "fire", XR.ACTION_TYPE_BOOLEAN, "Fire"),
    aimr = makeAction(set, "aim_r", XR.ACTION_TYPE_POSE, "Right Aim"),
  }

  local function suggest(profile, list)
    local arr = ffi.new("XrActionSuggestedBinding[?]", #list)
    for i, p in ipairs(list) do
      arr[i - 1].action = p[1]
      arr[i - 1].binding = toPath(p[2])
    end
    local info = ffi.new("XrInteractionProfileSuggestedBinding")
    info.type = XR.TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING
    info.interactionProfile = toPath(profile)
    info.countSuggestedBindings = #list
    info.suggestedBindings = arr
    check(xr.xrSuggestInteractionProfileBindings(instance, info),
          "suggest " .. profile)
  end

  -- the sticks-and-buttons layout Touch and Index share
  local sticks = {
    { A.move, "/user/hand/left/input/thumbstick" },
    { A.look, "/user/hand/right/input/thumbstick" },
    { A.a, "/user/hand/right/input/a/click" },
    { A.b, "/user/hand/right/input/b/click" },
    { A.a, "/user/hand/left/input/x/click" },
    { A.b, "/user/hand/left/input/y/click" },
    { A.start, "/user/hand/left/input/trigger/value" },
    { A.start, "/user/hand/right/input/trigger/value" },
    { A.toggle, "/user/hand/left/input/thumbstick/click" },
    { A.gripl, "/user/hand/left/input/squeeze/value" },
    { A.gripr, "/user/hand/right/input/squeeze/value" },
    { A.handl, "/user/hand/left/input/grip/pose" },
    { A.handr, "/user/hand/right/input/grip/pose" },
    { A.fire, "/user/hand/right/input/trigger/value" },
    { A.aimr, "/user/hand/right/input/aim/pose" },
  }
  -- Index has X/Y on no hand -- its A/B exist on BOTH -- so the two X/Y
  -- rows are swapped for left A/B there
  local index = {}
  for i, p in ipairs(sticks) do index[i] = p end
  index[5] = { A.a, "/user/hand/left/input/a/click" }
  index[6] = { A.b, "/user/hand/left/input/b/click" }

  pcall(suggest, "/interaction_profiles/oculus/touch_controller", sticks)
  pcall(suggest, "/interaction_profiles/valve/index_controller", index)
  pcall(suggest, "/interaction_profiles/microsoft/motion_controller", {
    { A.move, "/user/hand/left/input/thumbstick" },
    { A.look, "/user/hand/right/input/thumbstick" },
    { A.a, "/user/hand/right/input/trackpad/click" },
    { A.b, "/user/hand/left/input/trackpad/click" },
    { A.start, "/user/hand/left/input/trigger/value" },
    { A.start, "/user/hand/right/input/trigger/value" },
    { A.toggle, "/user/hand/left/input/thumbstick/click" },
    { A.gripl, "/user/hand/left/input/squeeze/click" },
    { A.gripr, "/user/hand/right/input/squeeze/click" },
    { A.handl, "/user/hand/left/input/grip/pose" },
    { A.handr, "/user/hand/right/input/grip/pose" },
    { A.fire, "/user/hand/right/input/trigger/value" },
    { A.aimr, "/user/hand/right/input/aim/pose" },
  })
  pcall(suggest, "/interaction_profiles/khr/simple_controller", {
    { A.a, "/user/hand/right/input/select/click" },
    { A.a, "/user/hand/left/input/select/click" },
    { A.start, "/user/hand/right/input/menu/click" },
    { A.start, "/user/hand/left/input/menu/click" },
  })

  local function handSpace(action)
    local info = ffi.new("XrActionSpaceCreateInfo")
    info.type = XR.TYPE_ACTION_SPACE_CREATE_INFO
    info.action = action
    info.poseInActionSpace.orientation.w = 1
    local out = ffi.new("XrSpace[1]")
    check(xr.xrCreateActionSpace(session, info, out), "xrCreateActionSpace")
    return out[0]
  end
  -- the aim pose gets a space of its own; a runtime that refused the
  -- binding simply never locates it, and the gun falls back to the grip
  local spaces = { handl = handSpace(A.handl), handr = handSpace(A.handr) }
  local okAim, aimSpace = pcall(handSpace, A.aimr)
  if okAim and aimSpace then spaces.aimr = aimSpace end

  local sets = ffi.new("XrActionSet[1]")
  sets[0] = set
  local att = ffi.new("XrSessionActionSetsAttachInfo")
  att.type = XR.TYPE_SESSION_ACTION_SETS_ATTACH_INFO
  att.countActionSets = 1
  att.actionSets = sets
  check(xr.xrAttachSessionActionSets(session, att),
        "xrAttachSessionActionSets")

  local active = ffi.new("XrActiveActionSet[1]")
  active[0].actionSet = set
  input = { set = set, A = A, spaces = spaces, active = active }
end

-- Sync and read this frame's controller state as one plain table, or nil
-- when there is none to read (no input attached, session unfocused) --
-- which callers treat as everything released.
function VRXR.input(time)
  if not (running and input) then return nil end
  local out = nil
  pcall(function()
    local si = ffi.new("XrActionsSyncInfo")
    si.type = XR.TYPE_ACTIONS_SYNC_INFO
    si.countActiveActionSets = 1
    si.activeActionSets = input.active
    if tonumber(xr.xrSyncActions(session, si)) ~= 0 then return end

    local gi = ffi.new("XrActionStateGetInfo")
    gi.type = XR.TYPE_ACTION_STATE_GET_INFO
    local function readBool(action)
      gi.action = action
      local st = ffi.new("XrActionStateBoolean")
      st.type = XR.TYPE_ACTION_STATE_BOOLEAN
      xr.xrGetActionStateBoolean(session, gi, st)
      return st.currentState ~= 0, st.changedSinceLastSync ~= 0
    end
    local function readVec2(action)
      gi.action = action
      local st = ffi.new("XrActionStateVector2f")
      st.type = XR.TYPE_ACTION_STATE_VECTOR2F
      xr.xrGetActionStateVector2f(session, gi, st)
      return st.currentState.x, st.currentState.y
    end
    local function readFloat(action)
      gi.action = action
      local st = ffi.new("XrActionStateFloat")
      st.type = XR.TYPE_ACTION_STATE_FLOAT
      xr.xrGetActionStateFloat(session, gi, st)
      return st.currentState
    end

    local A = input.A
    local o = {}
    o.moveX, o.moveY = readVec2(A.move)
    o.lookX, o.lookY = readVec2(A.look)
    o.a, o.aChanged = readBool(A.a)
    o.b, o.bChanged = readBool(A.b)
    o.start, o.startChanged = readBool(A.start)
    o.toggle, o.toggleChanged = readBool(A.toggle)
    o.fire, o.fireChanged = readBool(A.fire)
    o.gripL = readFloat(A.gripl)
    o.gripR = readFloat(A.gripr)

    -- hand heights in LOCAL metres, for the grab-drag; absent when the
    -- runtime has no valid position for a hand this frame
    local loc = ffi.new("XrSpaceLocation")
    for name, spc in pairs(input.spaces) do
      loc.type = XR.TYPE_SPACE_LOCATION
      loc.next = nil
      loc.locationFlags = 0
      if tonumber(xr.xrLocateSpace(spc, space, time, loc)) == 0 then
        local fl = tonumber(loc.locationFlags) or 0
        if fl % 4 >= XR.SPACE_LOCATION_POSITION_VALID_BIT then
          o[name .. "Y"] = loc.pose.position.y
          -- and the whole pose when the orientation is valid too
          -- (bit 0x1): the hand-held pokedex stands on it
          if fl % 2 >= 1 then
            local p, q = loc.pose.position, loc.pose.orientation
            o[name] = { pos = { p.x, p.y, p.z },
                        quat = { q.x, q.y, q.z, q.w } }
          end
        end
      end
    end
    out = o
  end)
  return out
end

-- ------- lifecycle

-- Bring the whole stack up, or say exactly why not. Never throws; call
-- again after fixing whatever status() names.
function VRXR.start(quadW, quadH)
  if session then return true end
  local ok, err = pcall(function()
    if not VRGL.load() then error(VRGL.status(), 0) end
    xr = xr or loadLoader()

    -- instance, asking only for the one extension this rides on
    local extName = ffi.new("const char*[1]")
    local extStr = ffi.new("char[?]", 32, "XR_KHR_opengl_enable")
    extName[0] = extStr
    local ici = ffi.new("XrInstanceCreateInfo")
    ici.type = XR.TYPE_INSTANCE_CREATE_INFO
    ffi.copy(ici.applicationInfo.applicationName, "DramaticShapeVoxelMod")
    ici.applicationInfo.applicationVersion = 1
    ffi.copy(ici.applicationInfo.engineName, "LOVE")
    ici.applicationInfo.engineVersion = 11
    ici.applicationInfo.apiVersion = XR.API_VERSION_1_0
    ici.enabledExtensionCount = 1
    ici.enabledExtensionNames = extName
    local inst = ffi.new("XrInstance[1]")
    check(xr.xrCreateInstance(ici, inst), "xrCreateInstance")
    instance = inst[0]

    -- a headset
    local sgi = ffi.new("XrSystemGetInfo")
    sgi.type = XR.TYPE_SYSTEM_GET_INFO
    sgi.formFactor = XR.FORM_FACTOR_HEAD_MOUNTED_DISPLAY
    local sys = ffi.new("XrSystemId[1]")
    check(xr.xrGetSystem(instance, sgi, sys), "xrGetSystem")
    systemId = sys[0]

    -- the spec REQUIRES this call before the session may exist
    local pfn = ffi.new("void*[1]")
    check(xr.xrGetInstanceProcAddr(instance,
          "xrGetOpenGLGraphicsRequirementsKHR", pfn),
          "xrGetInstanceProcAddr")
    local reqs = ffi.new("XrGraphicsRequirementsOpenGLKHR")
    reqs.type = XR.TYPE_GRAPHICS_REQUIREMENTS_OPENGL_KHR
    check(ffi.cast("PFN_xrGetOpenGLGraphicsRequirementsKHR", pfn[0])(
          instance, systemId, reqs), "xrGetOpenGLGraphicsRequirementsKHR")

    -- the session, married to LOVE's own GL context. The binding is
    -- allocated as a one-element ARRAY: LuaJIT decays arrays to pointers
    -- on assignment, which is what chaining it into `next` needs -- a
    -- bare struct would not convert.
    local hdc, hglrc = VRGL.contexts()
    if hdc == nil or hglrc == nil then
      error("no current GL context to bind (is a window up?)", 0)
    end
    local binding = ffi.new("XrGraphicsBindingOpenGLWin32KHR[1]")
    binding[0].type = XR.TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR
    binding[0].hDC, binding[0].hGLRC = hdc, hglrc
    local sci = ffi.new("XrSessionCreateInfo")
    sci.type = XR.TYPE_SESSION_CREATE_INFO
    sci.next = binding
    sci.systemId = systemId
    local ses = ffi.new("XrSession[1]")
    check(xr.xrCreateSession(instance, sci, ses), "xrCreateSession")
    session = ses[0]

    -- LOCAL space: origin where the head was, +Y up, -Z ahead
    local rsci = ffi.new("XrReferenceSpaceCreateInfo")
    rsci.type = XR.TYPE_REFERENCE_SPACE_CREATE_INFO
    rsci.referenceSpaceType = XR.REFERENCE_SPACE_TYPE_LOCAL
    rsci.poseInReferenceSpace.orientation.w = 1
    local spc = ffi.new("XrSpace[1]")
    check(xr.xrCreateReferenceSpace(session, rsci, spc),
          "xrCreateReferenceSpace")
    space = spc[0]

    -- the two eyes at the runtime's recommended size
    local count = ffi.new("uint32_t[1]")
    check(xr.xrEnumerateViewConfigurationViews(instance, systemId,
          XR.VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, count, nil),
          "xrEnumerateViewConfigurationViews(count)")
    if count[0] < 2 then error("stereo view configuration missing", 0) end
    views = ffi.new("XrViewConfigurationView[?]", count[0])
    for i = 0, count[0] - 1 do
      views[i].type = XR.TYPE_VIEW_CONFIGURATION_VIEW
    end
    check(xr.xrEnumerateViewConfigurationViews(instance, systemId,
          XR.VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, count[0], count, views),
          "xrEnumerateViewConfigurationViews")

    local format = pickFormat()
    for i = 1, 2 do
      eyes[i] = makeSwapchain(views[i - 1].recommendedImageRectWidth,
                              views[i - 1].recommendedImageRectHeight,
                              format)
    end
    quad = makeSwapchain(quadW or 1024, quadH or 768, format)

    viewsBuf = ffi.new("XrView[2]")
  end)
  if not ok then
    VRXR.stop()
    status = tostring(err)
    return false
  end
  -- controllers, in their own pcall: a runtime that refuses the action
  -- system costs the controllers and nothing else -- the head still
  -- tracks and the desk's own inputs still play
  local okIn, errIn = pcall(setupInput)
  if not okIn then
    input = nil
    print("[DRAMATIC_SHAPE] VR controllers unavailable: " .. tostring(errIn))
  end
  status = "session created"
  return true
end

-- Tear the whole stack down (setting toggled off, or a fatal state).
function VRXR.stop()
  running = false
  if session then pcall(function() xr.xrDestroySession(session) end) end
  if instance then pcall(function() xr.xrDestroyInstance(instance) end) end
  session, space, instance, systemId = nil, nil, nil, nil
  eyes, quad, views, viewsBuf, lastViews = {}, nil, nil, nil, nil
  input = nil          -- its handles died with the instance
end

-- ------- the frame loop

-- Pump the runtime's events: begin the session when it says READY, end it
-- when it says STOPPING. Returns false when the session is gone for good.
function VRXR.poll()
  if not session then return false end
  local alive = true
  pcall(function()
    -- a one-element array, so the retype cast below has a pointer to
    -- decay from (ffi.cast does not take a bare struct's address)
    local buf = ffi.new("XrEventDataBuffer[1]")
    while true do
      buf[0].type = XR.TYPE_EVENT_DATA_BUFFER
      buf[0].next = nil
      if tonumber(xr.xrPollEvent(instance, buf)) ~= 0 then break end
      if buf[0].type == XR.TYPE_EVENT_DATA_SESSION_STATE_CHANGED then
        local ev = ffi.cast("XrEventDataSessionStateChanged*", buf)
        sessionState = tonumber(ev.state)
        if sessionState == XR.SESSION_STATE_READY and not running then
          local sbi = ffi.new("XrSessionBeginInfo")
          sbi.type = XR.TYPE_SESSION_BEGIN_INFO
          sbi.primaryViewConfigurationType =
            XR.VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO
          if tonumber(xr.xrBeginSession(session, sbi)) == 0 then
            running = true
            status = "running"
          end
        elseif sessionState == XR.SESSION_STATE_STOPPING then
          pcall(function() xr.xrEndSession(session) end)
          running = false
          status = "stopped by runtime"
        elseif sessionState == XR.SESSION_STATE_EXITING
               or sessionState == XR.SESSION_STATE_LOSS_PENDING then
          alive = false
        end
      end
    end
  end)
  if not alive then VRXR.stop() end
  return session ~= nil
end

function VRXR.isRunning()
  return running
end

-- Block until the runtime wants the next frame; returns its predicted
-- display time and whether rendering is worth doing, or nil off-session.
function VRXR.waitFrame()
  if not running then return nil end
  local time, should = nil, false
  local ok = pcall(function()
    local fs = ffi.new("XrFrameState")
    fs.type = XR.TYPE_FRAME_STATE
    check(xr.xrWaitFrame(session, nil, fs), "xrWaitFrame")
    check(xr.xrBeginFrame(session, nil), "xrBeginFrame")
    time = fs.predictedDisplayTime
    should = fs.shouldRender ~= 0
  end)
  if not ok then return nil end
  return time, should
end

-- Where each eye is and what it sees, at `time`, as plain tables (and
-- kept as cdata for the layer submit). nil when tracking is not live.
function VRXR.locateViews(time)
  if not running then return nil end
  local out = nil
  pcall(function()
    local vli = ffi.new("XrViewLocateInfo")
    vli.type = XR.TYPE_VIEW_LOCATE_INFO
    vli.viewConfigurationType = XR.VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO
    vli.displayTime = time
    vli.space = space
    local vs = ffi.new("XrViewState")
    vs.type = XR.TYPE_VIEW_STATE
    local count = ffi.new("uint32_t[1]")
    viewsBuf[0].type, viewsBuf[1].type = XR.TYPE_VIEW, XR.TYPE_VIEW
    check(xr.xrLocateViews(session, vli, vs, 2, count, viewsBuf),
          "xrLocateViews")
    if count[0] < 2 then return end
    out = {}
    for i = 1, 2 do
      local v = viewsBuf[i - 1]
      out[i] = {
        pose = {
          pos = { v.pose.position.x, v.pose.position.y, v.pose.position.z },
          quat = { v.pose.orientation.x, v.pose.orientation.y,
                   v.pose.orientation.z, v.pose.orientation.w },
        },
        fov = { angleLeft = v.fov.angleLeft, angleRight = v.fov.angleRight,
                angleUp = v.fov.angleUp, angleDown = v.fov.angleDown },
        w = eyes[i].w, h = eyes[i].h,
      }
    end
  end)
  lastViews = out
  return out
end

-- Acquire eye `i`'s next texture for writing. Pair with releaseEye.
function VRXR.acquireEye(i)
  local e = eyes[i]
  if not (running and e) then return nil end
  local tex = nil
  pcall(function()
    local idx = ffi.new("uint32_t[1]")
    check(xr.xrAcquireSwapchainImage(e.swapchain, nil, idx),
          "xrAcquireSwapchainImage")
    local wi = ffi.new("XrSwapchainImageWaitInfo")
    wi.type = XR.TYPE_SWAPCHAIN_IMAGE_WAIT_INFO
    wi.timeout = XR.INFINITE_DURATION
    check(xr.xrWaitSwapchainImage(e.swapchain, wi), "xrWaitSwapchainImage")
    tex = e.images[idx[0] + 1]
  end)
  return tex, e.w, e.h
end

function VRXR.releaseEye(i)
  local e = eyes[i]
  if not (running and e) then return end
  pcall(function() xr.xrReleaseSwapchainImage(e.swapchain, nil) end)
end

function VRXR.acquireQuad()
  if not (running and quad) then return nil end
  local tex = nil
  pcall(function()
    local idx = ffi.new("uint32_t[1]")
    check(xr.xrAcquireSwapchainImage(quad.swapchain, nil, idx),
          "xrAcquireSwapchainImage(quad)")
    local wi = ffi.new("XrSwapchainImageWaitInfo")
    wi.type = XR.TYPE_SWAPCHAIN_IMAGE_WAIT_INFO
    wi.timeout = XR.INFINITE_DURATION
    check(xr.xrWaitSwapchainImage(quad.swapchain, wi), "xrWaitSwapchainImage")
    tex = quad.images[idx[0] + 1]
  end)
  return tex, quad.w, quad.h
end

function VRXR.releaseQuad()
  if not (running and quad) then return end
  pcall(function() xr.xrReleaseSwapchainImage(quad.swapchain, nil) end)
end

-- Close the frame. `world` submits the projection layer from the LAST
-- locateViews (both eyes assumed blitted); `quadOpts` floats the UI panel:
-- { pos = {x,y,z}, quat = {x,y,z,w}, width = metres,
--   crop = {x, y, w, h} or nil }. Either may be nil. `crop` shows only
-- that sub-rect of the quad's texture -- GL image coordinates, origin
-- bottom-left, exactly as the front-buffer copy landed the window -- and
-- the panel's aspect follows the rect (the GB letterbox's near-square
-- frame) instead of the whole texture's.
function VRXR.endFrame(time, world, quadOpts)
  if not running then return end
  pcall(function()
    -- every layer is a one-element ARRAY so it decays to a pointer when
    -- stored into the layer list; the locals also anchor the cdata
    -- against collection until xrEndFrame has read it
    local layers = {}
    local projViews, proj, quadLayer

    if world and lastViews then
      projViews = ffi.new("XrCompositionLayerProjectionView[2]")
      for i = 0, 1 do
        projViews[i].type = XR.TYPE_COMPOSITION_LAYER_PROJECTION_VIEW
        projViews[i].pose = viewsBuf[i].pose
        projViews[i].fov = viewsBuf[i].fov
        projViews[i].subImage.swapchain = eyes[i + 1].swapchain
        projViews[i].subImage.imageRect.extent.width = eyes[i + 1].w
        projViews[i].subImage.imageRect.extent.height = eyes[i + 1].h
      end
      proj = ffi.new("XrCompositionLayerProjection[1]")
      proj[0].type = XR.TYPE_COMPOSITION_LAYER_PROJECTION
      proj[0].space = space
      proj[0].viewCount = 2
      proj[0].views = projViews
      layers[#layers + 1] = proj
    end

    if quadOpts and quad then
      quadLayer = ffi.new("XrCompositionLayerQuad[1]")
      quadLayer[0].type = XR.TYPE_COMPOSITION_LAYER_QUAD
      quadLayer[0].space = space
      quadLayer[0].eyeVisibility = XR.EYE_VISIBILITY_BOTH
      quadLayer[0].subImage.swapchain = quad.swapchain
      local cr = quadOpts.crop
      if cr then
        quadLayer[0].subImage.imageRect.offset.x = cr[1]
        quadLayer[0].subImage.imageRect.offset.y = cr[2]
        quadLayer[0].subImage.imageRect.extent.width = cr[3]
        quadLayer[0].subImage.imageRect.extent.height = cr[4]
      else
        quadLayer[0].subImage.imageRect.extent.width = quad.w
        quadLayer[0].subImage.imageRect.extent.height = quad.h
      end
      local p, q = quadOpts.pos or { 0, 0, -1 }, quadOpts.quat or { 0, 0, 0, 1 }
      quadLayer[0].pose.position.x = p[1]
      quadLayer[0].pose.position.y = p[2]
      quadLayer[0].pose.position.z = p[3]
      quadLayer[0].pose.orientation.x = q[1]
      quadLayer[0].pose.orientation.y = q[2]
      quadLayer[0].pose.orientation.z = q[3]
      quadLayer[0].pose.orientation.w = q[4]
      local w = quadOpts.width or 1.0
      quadLayer[0].size.width = w
      if cr then
        quadLayer[0].size.height = w * (cr[4] / math.max(1, cr[3]))
      else
        quadLayer[0].size.height = w * (quad.h / quad.w)
      end
      layers[#layers + 1] = quadLayer
    end

    local arr = ffi.new("const void*[?]", math.max(1, #layers))
    for i = 1, #layers do arr[i - 1] = layers[i] end
    local fei = ffi.new("XrFrameEndInfo")
    fei.type = XR.TYPE_FRAME_END_INFO
    fei.displayTime = time
    fei.environmentBlendMode = XR.ENVIRONMENT_BLEND_MODE_OPAQUE
    fei.layerCount = #layers
    fei.layers = arr
    xr.xrEndFrame(session, fei)
  end)
end

function VRXR.quadSize()
  if quad then return quad.w, quad.h end
  return nil
end

function VRXR.status()
  return status
end

return VRXR
