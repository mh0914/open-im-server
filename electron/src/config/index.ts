export const APP_NAME = "OpenCorp-Base";
export const APP_VERSION = "v3.8.3";
export const SDK_VERSION = "SDK(ffi) v3.8.3";
export const isSaveLog = process.env.NODE_ENV !== "development";
export const IS_SKIP_SMS_VERIFY = import.meta.env.VITE_SKIP_SMS_VERIFY === "true";
export const LOCAL_VERIFY_CODE =
  import.meta.env.VITE_LOCAL_VERIFY_CODE || "666666";
