#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import "ghostty.h"

static ghostty_app_t runtime;
static NSString *root;
static NSString *evidence;
static int listener = -1, peer = -1;
static NSUInteger inputBytes, snapshotCount;
static double snapshotTotalMS, snapshotMaxMS;
static NSData *lastSent;
static NSUInteger sentFrames, sentBytes;
static NSMutableArray *windows;

@interface SurfaceView : NSView
@property(nonatomic, assign) ghostty_surface_t surface;
@end
@implementation SurfaceView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
  const char *text = event.characters.UTF8String;
  ghostty_input_key_s key = {
    .action = GHOSTTY_ACTION_PRESS, .keycode = event.keyCode, .text = text,
  };
  ghostty_surface_key(self.surface, key);
}
@end
static SurfaceView *host, *client;
static void wakeup(void *data) {
  dispatch_async(dispatch_get_main_queue(), ^{ if (runtime) ghostty_app_tick(runtime); });
}
static bool action(ghostty_app_t app, ghostty_target_s target, ghostty_action_s value) { return false; }
static bool clipboardRead(void *data, ghostty_clipboard_e kind, void *state) { return false; }
static void clipboardConfirm(void *data, const char *text, void *state, ghostty_clipboard_request_e request) {}
static void clipboardWrite(void *data, ghostty_clipboard_e kind, const ghostty_clipboard_content_s *content, size_t count, bool confirm) {}
static void closeSurface(void *data, bool alive) {}
static NSData *snapshot(ghostty_surface_t surface) {
  ghostty_text_s value = {0};
  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
  if (!ghostty_surface_spike_snapshot(surface, &value)) return nil;
  double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
  snapshotCount++; snapshotTotalMS += ms; snapshotMaxMS = MAX(snapshotMaxMS, ms);
  NSData *data = [NSData dataWithBytes:value.text length:value.text_len];
  ghostty_surface_free_text(surface, &value);
  return data;
}
static NSData *plain(ghostty_surface_t surface) {
  ghostty_text_s value = {0};
  ghostty_selection_s selection = {
    .top_left = {.tag = GHOSTTY_POINT_ACTIVE, .coord = GHOSTTY_POINT_COORD_TOP_LEFT},
    .bottom_right = {.tag = GHOSTTY_POINT_ACTIVE, .coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT},
  };
  if (!ghostty_surface_read_text(surface, selection, &value)) return nil;
  NSData *data = [NSData dataWithBytes:value.text length:value.text_len];
  ghostty_surface_free_text(surface, &value);
  return data;
}
static SurfaceView *makeSurface(NSString *title, NSString *command, CGFloat x) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(x, 200, 650, 380)
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
      backing:NSBackingStoreBuffered defer:NO];
  window.title = title;
  window.releasedWhenClosed = NO;
  SurfaceView *view = [[SurfaceView alloc] initWithFrame:NSMakeRect(0, 0, 650, 380)];
  view.wantsLayer = YES;
  window.contentView = view;
  [windows addObject:window];
  [window makeKeyAndOrderFront:nil];
  ghostty_surface_config_s config = ghostty_surface_config_new();
  config.platform_tag = GHOSTTY_PLATFORM_MACOS;
  config.platform.macos.nsview = (__bridge void *)view;
  config.scale_factor = window.backingScaleFactor;
  config.font_size = 13;
  config.command = command.UTF8String;
  config.working_directory = root.UTF8String;
  view.surface = ghostty_surface_new(runtime, &config);
  NSCAssert(view.surface, @"surface creation failed");
  ghostty_surface_set_content_scale(view.surface, config.scale_factor, config.scale_factor);
  // Both replicas use the same pixel size and font metrics in this experiment.
  ghostty_surface_set_size(view.surface, 650 * config.scale_factor, 380 * config.scale_factor);
  ghostty_surface_set_focus(view.surface, true);
  ghostty_surface_set_occlusion(view.surface, true);
  [window makeFirstResponder:view];
  return view;
}
static void saveStage(NSString *name) {
  for (NSUInteger i = 0; i < 2; i++) {
    SurfaceView *view = i ? client : host;
    NSString *side = i ? @"client" : @"host";
    NSString *stem = [evidence stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", name, side]];
    [plain(view.surface) writeToFile:[stem stringByAppendingString:@".txt"] atomically:YES];
    [snapshot(view.surface) writeToFile:[stem stringByAppendingString:@".vt"] atomically:YES];
  }
}
static void type(ghostty_surface_t surface, const char *text) {
  ghostty_input_key_s key = {.action = GHOSTTY_ACTION_PRESS, .keycode = 0, .text = text};
  ghostty_surface_key(surface, key);
}
static void pump(void) {
  ghostty_app_tick(runtime);
  if (peer < 0) {
    peer = accept(listener, NULL, NULL);
    if (peer >= 0) {
      lastSent = nil;
      int yes = 1;
      setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
      struct timeval timeout = {.tv_sec = 0, .tv_usec = 50000};
      setsockopt(peer, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    }
  }
  if (peer >= 0) {
    char input[4096];
    ssize_t count = recv(peer, input, sizeof(input), MSG_DONTWAIT);
    if (count > 0) {
      inputBytes += count;
      NSString *inputPath = [evidence stringByAppendingPathComponent:@"input.bin"];
      if (![[NSFileManager defaultManager] fileExistsAtPath:inputPath])
        [[NSData data] writeToFile:inputPath atomically:YES];
      NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:inputPath];
      [handle seekToEndOfFile];
      [handle writeData:[NSData dataWithBytes:input length:count]];
      [handle closeFile];
      // These bytes already passed through the client terminal input encoder.
      // The text callback is a paste API and would wrap bracketed paste again.
      NSMutableString *binding = [NSMutableString stringWithString:@"text:"];
      for (ssize_t i = 0; i < count; i++) [binding appendFormat:@"\\x%02x", (unsigned char)input[i]];
      ghostty_surface_binding_action(host.surface, binding.UTF8String, strlen(binding.UTF8String));
    } else if (count == 0) {
      close(peer); peer = -1;
      return;
    }
    NSData *data = snapshot(host.surface);
    if ([data isEqualToData:lastSent]) return;
    lastSent = data;
    sentFrames++; sentBytes += data.length;
    uint32_t length = htonl((uint32_t)data.length);
    NSMutableData *frame = [NSMutableData dataWithBytes:&length length:4];
    [frame appendData:data];
    const uint8_t *bytes = frame.bytes;
    NSUInteger offset = 0;
    while (offset < frame.length) {
      ssize_t n = send(peer, bytes + offset, frame.length - offset, 0);
      if (n <= 0) { close(peer); peer = -1; break; }
      offset += n;
    }
  }
  ghostty_surface_draw(host.surface);
  if (client.surface) ghostty_surface_draw(client.surface);
}
static void later(double seconds, dispatch_block_t block) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC), dispatch_get_main_queue(), block);
}
int main(int argc, char **argv) {
  @autoreleasepool {
    NSCAssert(argc == 4, @"usage: spike ROOT EVIDENCE PYTHON");
    root = @(argv[1]); evidence = @(argv[2]); NSString *python = @(argv[3]);
    [[NSFileManager defaultManager] createDirectoryAtPath:evidence withIntermediateDirectories:YES attributes:nil error:nil];
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSCAssert(ghostty_init(1, argv) == 0, @"ghostty init failed");
    ghostty_config_t config = ghostty_config_new();
    ghostty_config_load_file(config, [[root stringByAppendingPathComponent:@"config"] UTF8String]);
    ghostty_config_finalize(config);
    ghostty_runtime_config_s options = {
      .wakeup_cb = wakeup, .action_cb = action, .read_clipboard_cb = clipboardRead,
      .confirm_read_clipboard_cb = clipboardConfirm, .write_clipboard_cb = clipboardWrite,
      .close_surface_cb = closeSurface,
    };
    runtime = ghostty_app_new(&options, config);
    NSCAssert(runtime, @"runtime creation failed");
    windows = [NSMutableArray array];
    NSString *socketPath = [evidence stringByAppendingPathComponent:@"bridge.sock"];
    NSCAssert(socketPath.length < sizeof(((struct sockaddr_un *)0)->sun_path), @"socket path too long");
    NSCAssert(![[NSFileManager defaultManager] fileExistsAtPath:socketPath], @"use a fresh evidence directory");
    listener = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    strlcpy(addr.sun_path, socketPath.UTF8String, sizeof(addr.sun_path));
    NSCAssert(bind(listener, (struct sockaddr *)&addr, sizeof(addr)) == 0, @"bind failed");
    chmod(socketPath.UTF8String, 0600);
    listen(listener, 2); fcntl(listener, F_SETFL, O_NONBLOCK);
    NSString *hostCommand = [NSString stringWithFormat:@"%@ %@/fixture.py", python, root];
    NSString *clientCommand = [NSString stringWithFormat:@"%@ %@/relay.py %@", python, root, socketPath];
    host = makeSurface(@"Spike Host — live PTY", hostCommand, 30);
    __block int hostPID = 0;
    // Attach after the host has already emitted its screen.
    later(2, ^{ hostPID = ghostty_surface_pid(host.surface); client = makeSurface(@"Spike Client — snapshot replica", clientCommand, 710); });
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { pump(); }];
    later(5, ^{ saveStage(@"initial"); type(client.surface, "j"); });
    later(7, ^{ saveStage(@"input");
      close(peer); peer = -1;
      ghostty_surface_free(client.surface); client.surface = NULL;
      [client.window orderOut:nil];
      type(host.surface, "j");
    });
    later(9, ^{ client = makeSurface(@"Spike Client — reattached", clientCommand, 710); });
    later(12, ^{ saveStage(@"reconnect"); type(client.surface, "p"); });
    later(15, ^{ saveStage(@"primary"); type(client.surface, "a"); });
    later(getenv("SPIKE_HOLD") ? 300 : 18, ^{
      saveStage(@"alternate-again");
      ghostty_surface_size_s size = ghostty_surface_size(host.surface);
      NSDictionary *result = @{
        @"host_pid_before": @(hostPID), @"host_pid_after": @(ghostty_surface_pid(host.surface)),
        @"input_bytes": @(inputBytes), @"snapshot_count": @(snapshotCount),
        @"sent_frames": @(sentFrames), @"sent_bytes": @(sentBytes),
        @"snapshot_mean_ms": @(snapshotTotalMS / MAX(snapshotCount, 1)),
        @"snapshot_max_ms": @(snapshotMaxMS), @"columns": @(size.columns), @"rows": @(size.rows),
      };
      [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]
          writeToFile:[evidence stringByAppendingPathComponent:@"results.json"] atomically:YES];
      [timer invalidate];
      ghostty_surface_free(client.surface); ghostty_surface_free(host.surface);
      ghostty_app_free(runtime); runtime = NULL; ghostty_config_free(config);
      close(peer); close(listener); unlink(socketPath.UTF8String);
      [NSApp terminate:nil];
    });
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
