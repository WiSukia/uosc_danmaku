using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class BridgeProgram
{
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    public static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    public static string Str(IDictionary<string,object> data,string key) { object value;return data.TryGetValue(key,out value)&&value!=null?value.ToString():""; }
    public static int Num(IDictionary<string,object> data,string key) { int value;int.TryParse(Str(data,key),out value);return value; }
    public static void Write(string path,object value)
    {
        string tmp=path+".tmp";
        File.WriteAllText(tmp,Json.Serialize(value),new UTF8Encoding(false));
        if(File.Exists(path)) File.Replace(tmp,path,null);else File.Move(tmp,path);
    }
    [STAThread] public static int Main(string[] args)
    {
        string channel="";int pid=0;
        for(int i=0;i+1<args.Length;i+=2)
        {
            if(args[i]=="-Channel") channel=args[i+1];
            if(args[i]=="-OwnerProcessId") int.TryParse(args[i+1],out pid);
        }
        if(channel.Length==0) return 1;
        try
        {
            SetProcessDPIAware();Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            IntPtr owner=IntPtr.Zero;
            try { owner=Process.GetProcessById(pid).MainWindowHandle; } catch { }
            using(var bridge=new InputBridge(owner,pid))
            using(var timer=new System.Windows.Forms.Timer())
            {
                long commandSeq=0,eventSeq=0;int ownerCheck=0;
                var events=new List<Dictionary<string,object>>();
                bool pendingEvents=false;
                Action flush=delegate
                {
                    if(!pendingEvents)return;
                    try { Write(channel+".event",new Dictionary<string,object>{{"events",events}});pendingEvents=false; }
                    catch(IOException) { }
                };
                bridge.Event+=delegate(Dictionary<string,object> data)
                {
                    data["seq"]=++eventSeq;
                    events.Add(data);if(events.Count>64)events.RemoveAt(0);
                    pendingEvents=true;flush();
                };
                bridge.Prime();
                Write(channel+".ready",new Dictionary<string,object>{{"window",bridge.Handle.ToInt64()},
                    {"input",bridge.Edit.Handle.ToInt64()},{"pid",Process.GetCurrentProcess().Id}});
                timer.Interval=16;
                timer.Tick+=delegate
                {
                    try
                    {
                        if(File.Exists(channel+".control"))
                        {
                            var data=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(channel+".control",Encoding.UTF8));
                            long seq=Convert.ToInt64(data["seq"]);
                            if(seq>commandSeq) { commandSeq=seq;bridge.Apply(data); }
                        }
                    } catch(IOException) { } catch(ArgumentException) { }
                    bridge.CheckForeground();
                    flush();
                    if(++ownerCheck%60==0 && pid>0)
                    {
                        try { using(var process=Process.GetProcessById(pid)) if(process.HasExited)Application.ExitThread(); }
                        catch(ArgumentException) { Application.ExitThread(); }
                    }
                };
                timer.Start();Application.Run();
            }
            return 0;
        }
        catch(Exception error) { Console.Error.WriteLine(error.ToString());return 1; }
        finally
        {
            foreach(string suffix in new[]{".ready",".control",".control.tmp",".event",".event.tmp"})
                try { File.Delete(channel+suffix); } catch { }
        }
    }
}

public sealed class NativeOwner : IWin32Window
{
    public IntPtr Handle {get;private set;}
    public NativeOwner(IntPtr handle) {Handle=handle;}
}

public class ImeEdit : TextBox
{
    public bool Composing;
    public string Composition="";
    public int CompositionCursor;
    public event Action Changed;
    [DllImport("imm32.dll")] public static extern IntPtr ImmGetContext(IntPtr hwnd);
    [DllImport("imm32.dll")] public static extern bool ImmReleaseContext(IntPtr hwnd,IntPtr context);
    [DllImport("imm32.dll",CharSet=CharSet.Unicode)] static extern int ImmGetCompositionString(IntPtr context,uint index,byte[] buffer,int length);
    protected override bool IsInputKey(Keys keyData)
    {
        Keys key=keyData & Keys.KeyCode;
        return key==Keys.Enter || key==Keys.Escape || key==Keys.Tab || key==Keys.Up || key==Keys.Down || base.IsInputKey(keyData);
    }
    protected override void WndProc(ref Message m)
    {
        if(m.Msg==0x10D) {Composing=true;Composition="";}
        if(m.Msg==0x10F)
        {
            IntPtr context=ImmGetContext(Handle);
            if(context!=IntPtr.Zero)
            {
                int length=ImmGetCompositionString(context,8,null,0);
                if(length>=0)
                {
                    byte[] text=new byte[length];ImmGetCompositionString(context,8,text,length);
                    Composition=Encoding.Unicode.GetString(text);
                    CompositionCursor=Math.Max(0,ImmGetCompositionString(context,0x80,null,0));
                }
                ImmReleaseContext(Handle,context);
            }
        }
        base.WndProc(ref m);
        if(m.Msg==0x10E) {Composing=false;Composition="";}
        if((m.Msg==0x10D || m.Msg==0x10E || m.Msg==0x10F) && Changed!=null) Changed();
    }
    protected override void OnTextChanged(EventArgs e) {base.OnTextChanged(e);if(Changed!=null)Changed();}
    protected override void OnKeyUp(KeyEventArgs e)
    {
        base.OnKeyUp(e);
        if((e.KeyCode==Keys.Left || e.KeyCode==Keys.Right || e.KeyCode==Keys.Home || e.KeyCode==Keys.End ||
            (e.Control && e.KeyCode==Keys.A)) && Changed!=null)Changed();
    }
}

public class InputBridge : Form
{
    public readonly ImeEdit Edit;
    public event Action<Dictionary<string,object>> Event;
    IntPtr owner;
    readonly int ownerPid;
    Font ownedFont;
    bool active,applying,externalAway;
    int session,focusSerial,actionSerial;
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int left,top,right,bottom; }
    [StructLayout(LayoutKind.Sequential)] struct PointNative { public int x,y; }
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr hwnd,ref PointNative point);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool HideCaret(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    public InputBridge(IntPtr ownerHandle,int ownerProcessId=0)
    {
        owner=ownerHandle;ownerPid=ownerProcessId;
        Text="mpv 中文输入桥接";FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;
        StartPosition=FormStartPosition.Manual;ClientSize=new Size(2,2);BackColor=Color.Black;
        Region=new Region(Rectangle.Empty);ImeMode=ImeMode.On;
        Edit=new ImeEdit { BorderStyle=BorderStyle.None,ImeMode=ImeMode.On,MaxLength=1024,
            BackColor=Color.Black,ForeColor=Color.Black,Size=new Size(2,2) };
        Controls.Add(Edit);
        Edit.Changed+=PublishText;
        Edit.GotFocus+=delegate {HideCaret(Edit.Handle);};
        Edit.KeyDown+=delegate(object sender,KeyEventArgs e)
        {
            if(Edit.Composing) return;
            string key=e.KeyCode==Keys.Enter?"ENTER":e.KeyCode==Keys.Escape?"ESC":
                e.KeyCode==Keys.Up?"UP":e.KeyCode==Keys.Down?"DOWN":e.KeyCode==Keys.Tab?"TAB":null;
            if(key!=null)
            {
                var data=Snapshot();data["key"]=key;
                Emit(key=="ESC"?"cancel":"key",data);
                e.Handled=true;e.SuppressKeyPress=true;
            }
        };
    }
    protected override CreateParams CreateParams { get { var cp=base.CreateParams;cp.ExStyle|=0x80;return cp; } }
    protected override bool ShowWithoutActivation { get { return true; } }
    public void Prime() {IntPtr handle=Handle;handle=Edit.Handle;}
    void Emit(string kind,Dictionary<string,object> data)
    {
        data["kind"]=kind;data["session"]=session;
        if(Event!=null) Event(data);
    }
    public Dictionary<string,object> Snapshot()
    {
        int start=Edit.SelectionStart,end=Math.Min(Edit.Text.Length,start+Edit.SelectionLength);
        string head=Edit.Text.Substring(0,start),tail=Edit.Text.Substring(end);
        string comp=Edit.Composing?Edit.Composition:"";
        string display=head+comp+(comp.Length>0?tail:Edit.Text.Substring(start));
        int cursorChars=comp.Length>0?head.Length+Math.Min(comp.Length,Edit.CompositionCursor):end;
        return new Dictionary<string,object>{{"text",Edit.Text},{"display",display},
            {"cursor",Encoding.UTF8.GetByteCount(display.Substring(0,cursorChars))},
            {"selection_start",Encoding.UTF8.GetByteCount(head)},
            {"selection_end",Encoding.UTF8.GetByteCount(Edit.Text.Substring(0,end))},
            {"composition_start",comp.Length>0?Encoding.UTF8.GetByteCount(head):-1},
            {"composition_end",comp.Length>0?Encoding.UTF8.GetByteCount(head+comp):-1}};
    }
    public void PublishText()
    {
        if(!active || applying) return;
        HideCaret(Edit.Handle);Emit("text",Snapshot());
    }
    public void Apply(Dictionary<string,object> data)
    {
        bool nextActive=BridgeProgram.Str(data,"active")=="True";
        if(!nextActive) {active=false;Hide();return;}
        int nextSession=BridgeProgram.Num(data,"session");
        applying=true;
        try
        {
            if(nextSession!=session || (!Edit.Composing && Edit.Text!=BridgeProgram.Str(data,"text")))
            {
                Edit.Text=BridgeProgram.Str(data,"text");Edit.SelectionStart=Edit.Text.Length;
                Edit.Composing=false;Edit.Composition="";
            }
            active=true;session=nextSession;
            string family=BridgeProgram.Str(data,"font");
            int pixels=BridgeProgram.Num(data,"font_size");
            if(family.Length>0 && pixels>0 && (Edit.Font.Name!=family || Math.Abs(Edit.Font.Size-pixels)>0.5f))
            {
                Font old=ownedFont;ownedFont=new Font(family,pixels,GraphicsUnit.Pixel);Edit.Font=ownedFont;
                if(old!=null)old.Dispose();
            }
            int action=BridgeProgram.Num(data,"action_seq");
            if(action!=actionSerial)
            {
                actionSerial=action;
                string kind=BridgeProgram.Str(data,"action");
                if(kind=="submit") CompleteComposition();
                if(kind=="submit" || kind=="cancel") Emit(kind,Snapshot());
            }
            Rect rect;
            if(owner==IntPtr.Zero && ownerPid>0)
            {
                try {using(var process=Process.GetProcessById(ownerPid))owner=process.MainWindowHandle;}catch(ArgumentException) { }
            }
            if(owner!=IntPtr.Zero && GetClientRect(owner,out rect))
            {
                int width=Math.Max(1,BridgeProgram.Num(data,"width")),height=Math.Max(1,BridgeProgram.Num(data,"height"));
                var point=new PointNative {x=BridgeProgram.Num(data,"x")*(rect.right-rect.left)/width,
                    y=BridgeProgram.Num(data,"y")*(rect.bottom-rect.top)/height};
                ClientToScreen(owner,ref point);Location=new Point(point.x,point.y);
                if(!Visible && !IsIconic(owner)) Show(new NativeOwner(owner));
                int focus=BridgeProgram.Num(data,"focus");
                if(focus!=focusSerial) {focusSerial=focus;FocusInput();}
            }
        }
        finally {applying=false;}
    }
    [DllImport("imm32.dll")] static extern bool ImmNotifyIME(IntPtr context,uint action,uint index,uint value);
    void CompleteComposition()
    {
        if(!Edit.Composing) return;
        IntPtr context=ImeEdit.ImmGetContext(Edit.Handle);
        if(context!=IntPtr.Zero) {ImmNotifyIME(context,0x15,1,0);ImeEdit.ImmReleaseContext(Edit.Handle,context);}
    }
    public void FocusInput()
    {
        IntPtr foreground=GetForegroundWindow();
        if(owner!=IntPtr.Zero && (foreground==owner || foreground==Handle))
        {SetForegroundWindow(Handle);Activate();Edit.Focus();HideCaret(Edit.Handle);}
    }
    public void CheckForeground()
    {
        if(!active || owner==IntPtr.Zero)return;
        IntPtr foreground=GetForegroundWindow();
        if(foreground!=owner && foreground!=Handle) externalAway=true;
        else if(foreground==owner && externalAway) {externalAway=false;Emit("focus",new Dictionary<string,object>());}
        if(IsIconic(owner) && Visible) Hide();
        else if(!IsIconic(owner) && !Visible) Show(new NativeOwner(owner));
    }
    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if(disposing && ownedFont!=null)ownedFont.Dispose();
    }
}
