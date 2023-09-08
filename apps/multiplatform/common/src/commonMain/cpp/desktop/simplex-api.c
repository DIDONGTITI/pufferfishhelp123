#include <jni.h>
#include <string.h>
#include <stdlib.h>

// from the RTS
void hs_init(int * argc, char **argv[]);

JNIEXPORT void JNICALL
Java_chat_simplex_common_platform_CoreKt_initHS(JNIEnv *env, jclass clazz) {
    hs_init(NULL, NULL);
}

// from simplex-chat
typedef long* chat_ctrl;

extern char *chat_migrate_init(const char *path, const char *key, const char *confirm, chat_ctrl *ctrl);
extern char *chat_send_cmd(chat_ctrl ctrl, const char *cmd);
extern char *chat_recv_msg(chat_ctrl ctrl); // deprecated
extern char *chat_recv_msg_wait(chat_ctrl ctrl, const int wait);
extern char *chat_parse_markdown(const char *str);
extern char *chat_parse_server(const char *str);
extern char *chat_password_hash(const char *pwd, const char *salt);
extern char *chat_write_file(const char *path, char *ptr, int length);
extern char *chat_read_file(const char *path, const char *key, const char *nonce);
extern char *chat_encrypt_file(const char *from_path, const char *to_path);
extern char *chat_decrypt_file(const char *from_path, const char *key, const char *nonce, const char *to_path);

// As a reference: https://stackoverflow.com/a/60002045
jstring decode_to_utf8_string(JNIEnv *env, char *string) {
    jobject bb = (*env)->NewDirectByteBuffer(env, (void *)string, strlen(string));
    jclass cls_charset = (*env)->FindClass(env, "java/nio/charset/Charset");
    jmethodID mid_charset_forName = (*env)->GetStaticMethodID(env, cls_charset, "forName", "(Ljava/lang/String;)Ljava/nio/charset/Charset;");
    jobject charset = (*env)->CallStaticObjectMethod(env, cls_charset, mid_charset_forName, (*env)->NewStringUTF(env, "UTF-8"));

    jmethodID mid_decode = (*env)->GetMethodID(env, cls_charset, "decode", "(Ljava/nio/ByteBuffer;)Ljava/nio/CharBuffer;");
    jobject cb = (*env)->CallObjectMethod(env, charset, mid_decode, bb);

    jclass cls_char_buffer = (*env)->FindClass(env, "java/nio/CharBuffer");
    jmethodID mid_to_string = (*env)->GetMethodID(env, cls_char_buffer, "toString", "()Ljava/lang/String;");
    jstring res = (*env)->CallObjectMethod(env, cb, mid_to_string);

    (*env)->DeleteLocalRef(env, bb);
    (*env)->DeleteLocalRef(env, charset);
    (*env)->DeleteLocalRef(env, cb);
    return res;
}

char * encode_to_utf8_chars(JNIEnv *env, jstring string) {
    if (!string) return "";

    const jclass cls_string = (*env)->FindClass(env, "java/lang/String");
    const jmethodID mid_getBytes = (*env)->GetMethodID(env, cls_string, "getBytes", "(Ljava/lang/String;)[B");
    const jbyteArray jbyte_array = (jbyteArray) (*env)->CallObjectMethod(env, string, mid_getBytes, (*env)->NewStringUTF(env, "UTF-8"));
    jint length = (jint) (*env)->GetArrayLength(env, jbyte_array);
    jbyte *jbytes = malloc(length + 1);
    (*env)->GetByteArrayRegion(env, jbyte_array, 0, length, jbytes);
    // char * should be null terminated but jbyte * isn't. Terminate it with \0. Otherwise, Haskell will not see the end of string
    jbytes[length] = '\0';

    //for (int i = 0; i < length; ++i)
    //    fprintf(stderr, "%d: %02x\n", i, jbytes[i]);

    (*env)->DeleteLocalRef(env, jbyte_array);
    (*env)->DeleteLocalRef(env, cls_string);
    return (char *) jbytes;
}

JNIEXPORT jobjectArray JNICALL
Java_chat_simplex_common_platform_CoreKt_chatMigrateInit(JNIEnv *env, jclass clazz, jstring dbPath, jstring dbKey, jstring confirm) {
    const char *_dbPath = encode_to_utf8_chars(env, dbPath);
    const char *_dbKey = encode_to_utf8_chars(env, dbKey);
    const char *_confirm = encode_to_utf8_chars(env, confirm);
    long int *_ctrl = (long) 0;
    jstring res = decode_to_utf8_string(env, chat_migrate_init(_dbPath, _dbKey, _confirm, &_ctrl));
    (*env)->ReleaseStringUTFChars(env, dbPath, _dbPath);
    (*env)->ReleaseStringUTFChars(env, dbKey, _dbKey);
    (*env)->ReleaseStringUTFChars(env, dbKey, _confirm);

    // Creating array of Object's (boxed values can be passed, eg. Long instead of long)
    jobjectArray ret = (jobjectArray)(*env)->NewObjectArray(env, 2, (*env)->FindClass(env, "java/lang/Object"), NULL);
    // Java's String
    (*env)->SetObjectArrayElement(env, ret, 0, res);
    // Java's Long
    (*env)->SetObjectArrayElement(env, ret, 1,
        (*env)->NewObject(env, (*env)->FindClass(env, "java/lang/Long"),
        (*env)->GetMethodID(env, (*env)->FindClass(env, "java/lang/Long"), "<init>", "(J)V"),
        _ctrl));
    return ret;
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatSendCmd(JNIEnv *env, jclass clazz, jlong controller, jstring msg) {
    const char *_msg = encode_to_utf8_chars(env, msg);
    jstring res = decode_to_utf8_string(env, chat_send_cmd((void*)controller, _msg));
    (*env)->ReleaseStringUTFChars(env, msg, _msg);
    return res;
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatRecvMsg(JNIEnv *env, jclass clazz, jlong controller) {
    return decode_to_utf8_string(env, chat_recv_msg((void*)controller));
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatRecvMsgWait(JNIEnv *env, jclass clazz, jlong controller, jint wait) {
    return decode_to_utf8_string(env, chat_recv_msg_wait((void*)controller, wait));
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatParseMarkdown(JNIEnv *env, jclass clazz, jstring str) {
    const char *_str = encode_to_utf8_chars(env, str);
    jstring res = decode_to_utf8_string(env, chat_parse_markdown(_str));
    (*env)->ReleaseStringUTFChars(env, str, _str);
    return res;
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatParseServer(JNIEnv *env, jclass clazz, jstring str) {
    const char *_str = encode_to_utf8_chars(env, str);
    jstring res = decode_to_utf8_string(env, chat_parse_server(_str));
    (*env)->ReleaseStringUTFChars(env, str, _str);
    return res;
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatPasswordHash(JNIEnv *env, jclass clazz, jstring pwd, jstring salt) {
    const char *_pwd = encode_to_utf8_chars(env, pwd);
    const char *_salt = encode_to_utf8_chars(env, salt);
    jstring res = decode_to_utf8_string(env, chat_password_hash(_pwd, _salt));
    (*env)->ReleaseStringUTFChars(env, pwd, _pwd);
    (*env)->ReleaseStringUTFChars(env, salt, _salt);
    return res;
}

/*JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatWriteFile(JNIEnv *env, jclass clazz, jstring path, jbyteArray array) {
    const char *_path = encode_to_utf8_chars(env, path);
    jbyte* bufferPtr = (*env)->GetByteArrayElements(env, array, NULL);
    jsize len = (*env)->GetArrayLength(env, array);
    jstring res = decode_to_utf8_string(env, chat_write_file(_path, bufferPtr, len));
    (*env)->ReleaseByteArrayElements(env, array, bufferPtr, 0);
    (*env)->ReleaseStringUTFChars(env, path, _path);
    return res;
}*/

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatWriteFile(JNIEnv *env, jclass clazz, jstring path, jobject buffer) {
    const char *_path = encode_to_utf8_chars(env, path);
    jbyte *buff = (jbyte *) (*env)->GetDirectBufferAddress(env, buffer);
    jlong capacity = (*env)->GetDirectBufferCapacity(env, buffer);
    jstring res = decode_to_utf8_string(env, chat_write_file(_path, buff, capacity));
    (*env)->ReleaseStringUTFChars(env, path, _path);
    return res;
}

JNIEXPORT jbyteArray JNICALL
Java_chat_simplex_common_platform_CoreKt_chatReadFile(JNIEnv *env, jclass clazz, jstring path, jstring key, jstring nonce) {
    const char *_path = encode_to_utf8_chars(env, path);
    const char *_key = encode_to_utf8_chars(env, key);
    const char *_nonce = encode_to_utf8_chars(env, nonce);

    jbyte *res = chat_read_file(_path, _key, _nonce);
    (*env)->ReleaseStringUTFChars(env, path, _path);
    (*env)->ReleaseStringUTFChars(env, key, _key);
    (*env)->ReleaseStringUTFChars(env, nonce, _nonce);

    if (res[0] == 0) {
      int len = (res[4] << 24) & 0xff000000|
                (res[3] << 16) & 0x00ff0000|
                (res[2] << 8)  & 0x0000ff00|
                (res[1] << 0)  & 0x000000ff;
      jbyteArray arr = (*env)->NewByteArray(env, len);
      (*env)->SetByteArrayRegion(env, arr, 0, len, res + 5);
      return arr;
    } else {
      int len = strlen(res);
      jbyteArray arr = (*env)->NewByteArray(env, len + 10);
      (*env)->SetByteArrayRegion(env, arr, 10, len, res + 1);
      return arr;
    }
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatEncryptFile(JNIEnv *env, jclass clazz, jstring from_path, jstring to_path) {
    const char *_from_path = encode_to_utf8_chars(env, from_path);
    const char *_to_path = encode_to_utf8_chars(env, to_path);
    jstring res = decode_to_utf8_string(env, chat_encrypt_file(_from_path, _to_path));
    (*env)->ReleaseStringUTFChars(env, from_path, _from_path);
    (*env)->ReleaseStringUTFChars(env, to_path, _to_path);
    return res;
}

JNIEXPORT jstring JNICALL
Java_chat_simplex_common_platform_CoreKt_chatDecryptFile(JNIEnv *env, jclass clazz, jstring from_path, jstring key, jstring nonce, jstring to_path) {
    const char *_from_path = encode_to_utf8_chars(env, from_path);
    const char *_key = encode_to_utf8_chars(env, key);
    const char *_nonce = encode_to_utf8_chars(env, nonce);
    const char *_to_path = encode_to_utf8_chars(env, to_path);
    jstring res = decode_to_utf8_string(env, chat_decrypt_file(_from_path, _key, _nonce, _to_path));
    (*env)->ReleaseStringUTFChars(env, from_path, _from_path);
    (*env)->ReleaseStringUTFChars(env, key, _key);
    (*env)->ReleaseStringUTFChars(env,  nonce, _nonce);
    (*env)->ReleaseStringUTFChars(env, to_path, _to_path);
    return res;
}
