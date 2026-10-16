#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
/* Evidence: nst/iOS-Runtime-Headers, AXSettings.h (2018), exact declarations:
 + (id)sharedInstance;
 - (bool)callAudioRoutingAutoAnswerEnabled;
 - (void)setCallAudioRoutingAutoAnswerEnabled:(bool)arg1;
 Not proof of iOS 17.3 availability. Every ABI is checked on the actual device.
 No guessed Apple preferences domains, keys or Darwin notification names. */
static BOOL AACType(Method m, unsigned int index, const char *expected, BOOL result){
 if(!m)return NO;char type[64]={0};if(result)method_getReturnType(m,type,sizeof(type));else method_getArgumentType(m,index,type,sizeof(type));return strcmp(type,expected)==0;
}
static id AACSystemSettings(NSString **failure){
 static void *handle; if(!handle)handle=dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities",RTLD_LAZY|RTLD_LOCAL);
 Class cls=objc_getClass("AXSettings");SEL shared=sel_registerName("sharedInstance");Method cm=cls?class_getClassMethod(cls,shared):NULL;
 if(!handle||!cm||method_getNumberOfArguments(cm)!=2||!AACType(cm,0,"@",YES)){if(failure)*failure=@"AXSettings/sharedInstance 不可用或 ABI 不符";return nil;}
 @try {id obj=((id(*)(id,SEL))objc_msgSend)((id)cls,shared);
  if(!obj||![obj isKindOfClass:cls]){if(failure)*failure=@"AXSettings 实例类型不符";return nil;}
  Method g=class_getInstanceMethod(object_getClass(obj),sel_registerName("callAudioRoutingAutoAnswerEnabled"));
  Method s=class_getInstanceMethod(object_getClass(obj),sel_registerName("setCallAudioRoutingAutoAnswerEnabled:"));
  if(!g||!s||method_getNumberOfArguments(g)!=2||method_getNumberOfArguments(s)!=3||!AACType(g,0,"B",YES)||!AACType(s,0,"v",YES)||!AACType(s,2,"B",NO)){if(failure)*failure=@"系统自动接听 bool 读写访问器缺失/ABI 不符；禁止写入";return nil;}
  return obj;
 }@catch(NSException *e){if(failure)*failure=e.reason?:@"系统访问器异常";return nil;}
}
static BOOL AACSystemRead(BOOL *enabled,NSString **failure){
 id obj=AACSystemSettings(failure);if(!obj)return NO;
 @try {*enabled=((bool(*)(id,SEL))objc_msgSend)(obj,sel_registerName("callAudioRoutingAutoAnswerEnabled"));return YES;}@catch(NSException *e){if(failure)*failure=e.reason;return NO;}
}
static BOOL AACSystemDisable(NSString **failure){
 id obj=AACSystemSettings(failure);if(!obj)return NO;
 @try {((void(*)(id,SEL,bool))objc_msgSend)(obj,sel_registerName("setCallAudioRoutingAutoAnswerEnabled:"),false);return YES;}@catch(NSException *e){if(failure)*failure=e.reason;return NO;}
}
