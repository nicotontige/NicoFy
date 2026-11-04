#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

// Identify NicoFy consistently in the Windows shell.
inline constexpr wchar_t kNicoFyAppId[] = L"com.nicotontige.nicofy";

// Register the shell identity before creating any windows.
void ConfigureAppIdentity();

#endif  // RUNNER_APP_IDENTITY_H_
