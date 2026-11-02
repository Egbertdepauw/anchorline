// The app's display name, chosen by channel: the window title (main.cpp) and
// the Windows product name (Runner.rc), which decides the support folder. The
// build defines ANCHORLINE_NIGHTLY for the nightly (see windows/CMakeLists.txt).
//
// Plain preprocessor only, no C++: rc.exe includes this file too.
#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

#ifdef ANCHORLINE_NIGHTLY
#define APP_DISPLAY_NAME "Anchorline Nightly"
#else
#define APP_DISPLAY_NAME "Anchorline"
#endif

#endif  // RUNNER_APP_IDENTITY_H_
