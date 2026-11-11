// The few UnityEngine types the package's Unity half uses, with the signatures
// Unity's scripting reference gives them and no behaviour. They let
// clients/check_unity.sh compile that half with dotnet where there is no Unity,
// which catches a change to the C# SDK it no longer fits; they cannot show the
// package works in Unity itself.
//
// A new UnityEngine call in clients/unity_template gets its stub here, copied
// from the reference, never shaped to whatever makes the build pass.
#pragma warning disable CS0067, CS0660, CS0661, CS1591
using System;

namespace AOT
{
    [AttributeUsage(AttributeTargets.Method)]
    public sealed class MonoPInvokeCallbackAttribute : Attribute
    {
        public MonoPInvokeCallbackAttribute(Type type) { }
    }
}

namespace UnityEngine
{
    public class Object
    {
        public static void Destroy(Object obj) { }
        public static void DontDestroyOnLoad(Object target) { }
        public static bool operator ==(Object x, Object y) { return ReferenceEquals(x, y); }
        public static bool operator !=(Object x, Object y) { return !ReferenceEquals(x, y); }
    }

    public sealed class GameObject : Object { }

    public class Component : Object
    {
        public GameObject gameObject { get { return null; } }
        public Transform transform { get { return null; } }
        public T GetComponent<T>() { return default(T); }
    }

    public class Transform : Component
    {
        public Transform parent { get; set; }
    }

    public class Behaviour : Component
    {
        public bool enabled { get; set; }
    }

    public class MonoBehaviour : Behaviour { }

    public class AsyncOperation
    {
        public event Action<AsyncOperation> completed;
    }

    public static class Debug
    {
        public static void Log(object message) { }
        public static void LogWarning(object message) { }
        public static void LogWarning(object message, Object context) { }
        public static void LogError(object message) { }
        public static void LogException(Exception exception) { }
    }

    public static class Application
    {
        public static void OpenURL(string url) { }
    }

    public static class PlayerPrefs
    {
        public static string GetString(string key, string defaultValue) { return defaultValue; }
        public static void SetString(string key, string value) { }
        public static void Save() { }
    }

    public static class Screen
    {
        public static int width { get { return 0; } }
        public static int height { get { return 0; } }
    }

    public static class Mathf
    {
        public static float Min(float a, float b) { return a < b ? a : b; }
        public static int Min(int a, int b) { return a < b ? a : b; }
    }

    public struct Rect
    {
        public Rect(float x, float y, float width, float height) { }
    }

    public sealed class GUILayoutOption { }

    public class GUI
    {
        public static bool enabled { get; set; }
    }

    public class GUILayout
    {
        public static void BeginArea(Rect screenRect) { }
        public static void EndArea() { }
        public static void Label(string text, params GUILayoutOption[] options) { }
        public static bool Button(string text, params GUILayoutOption[] options) { return false; }
    }

    public enum RuntimeInitializeLoadType
    {
        AfterSceneLoad,
        BeforeSceneLoad,
        AfterAssembliesLoaded,
        BeforeSplashScreen,
        SubsystemRegistration,
    }

    [AttributeUsage(AttributeTargets.Method)]
    public sealed class RuntimeInitializeOnLoadMethodAttribute : Attribute
    {
        public RuntimeInitializeOnLoadMethodAttribute(RuntimeInitializeLoadType loadType) { }
    }

    [AttributeUsage(AttributeTargets.Class)]
    public sealed class DefaultExecutionOrder : Attribute
    {
        public DefaultExecutionOrder(int order) { }
    }

    [AttributeUsage(AttributeTargets.Class)]
    public sealed class DisallowMultipleComponent : Attribute { }

    [AttributeUsage(AttributeTargets.Class)]
    public sealed class AddComponentMenu : Attribute
    {
        public AddComponentMenu(string menuName) { }
    }

    [AttributeUsage(AttributeTargets.Class)]
    public sealed class HelpURLAttribute : Attribute
    {
        public HelpURLAttribute(string url) { }
    }

    [AttributeUsage(AttributeTargets.Class, AllowMultiple = true)]
    public sealed class RequireComponent : Attribute
    {
        public RequireComponent(Type requiredComponent) { }
    }

    [AttributeUsage(AttributeTargets.Field)]
    public sealed class SerializeField : Attribute { }

    [AttributeUsage(AttributeTargets.Field)]
    public class TooltipAttribute : Attribute
    {
        public TooltipAttribute(string tooltip) { }
    }
}

namespace UnityEngine.Networking
{
    public class DownloadHandler : IDisposable
    {
        public byte[] data { get { return null; } }
        public void Dispose() { }
    }

    public sealed class DownloadHandlerBuffer : DownloadHandler { }

    public class UploadHandler : IDisposable
    {
        public void Dispose() { }
    }

    public sealed class UploadHandlerRaw : UploadHandler
    {
        public UploadHandlerRaw(byte[] data) { }
    }

    public class UnityWebRequestAsyncOperation : AsyncOperation { }

    public class UnityWebRequest : IDisposable
    {
        public enum Result
        {
            InProgress,
            Success,
            ConnectionError,
            ProtocolError,
            DataProcessingError,
        }

        public UnityWebRequest(string url, string method) { }
        public DownloadHandler downloadHandler { get; set; }
        public UploadHandler uploadHandler { get; set; }
        public int timeout { get; set; }
        public Result result { get { return Result.InProgress; } }
        public long responseCode { get { return 0; } }
        public string error { get { return null; } }
        public void SetRequestHeader(string name, string value) { }
        public UnityWebRequestAsyncOperation SendWebRequest() { return null; }
        public void Dispose() { }
    }
}
