param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw "Ejecuta con powershell.exe -STA -File .\MonitorTray.ps1"
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class TrayDdc {
    [DllImport("user32.dll")]
    public static extern bool EnumDisplayMonitors(
        IntPtr hdc, IntPtr clip, MonitorEnum callback, IntPtr data);

    public delegate bool MonitorEnum(
        IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data);

    [DllImport("dxva2.dll", SetLastError=true)]
    public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(
        IntPtr monitor, out uint count);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
    public struct PhysicalMonitor {
        public IntPtr handle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)]
        public string description;
    }

    [DllImport("dxva2.dll", SetLastError=true)]
    public static extern bool GetPhysicalMonitorsFromHMONITOR(
        IntPtr monitor, uint count, [Out] PhysicalMonitor[] monitors);

    [DllImport("dxva2.dll", SetLastError=true)]
    public static extern bool SetVCPFeature(
        IntPtr monitor, byte code, uint value);

    [DllImport("dxva2.dll", SetLastError=true)]
    public static extern bool GetVCPFeatureAndVCPFeatureReply(
        IntPtr monitor, byte code, out byte type,
        out uint current, out uint maximum);

    [DllImport("dxva2.dll")]
    public static extern bool DestroyPhysicalMonitors(
        uint count, [In] PhysicalMonitor[] monitors);

    public static string SetBrightness(int value) {
        if (value < 0 || value > 100)
            throw new ArgumentOutOfRangeException("value");

        int found = 0, succeeded = 0;

        MonitorEnum callback = delegate(
            IntPtr h, IntPtr dc, IntPtr rect, IntPtr data) {

            uint count = 0;

            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(h, out count)
                || count == 0)
                return true;

            PhysicalMonitor[] monitors = new PhysicalMonitor[count];

            if (!GetPhysicalMonitorsFromHMONITOR(h, count, monitors))
                return true;

            try {
                foreach (PhysicalMonitor m in monitors) {
                    found++;
                    if (SetVCPFeature(m.handle, 0x10, (uint)value))
                        succeeded++;
                }
            }
            finally {
                DestroyPhysicalMonitors(count, monitors);
            }

            return true;
        };

        EnumDisplayMonitors(
            IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);

        return String.Format(
            "Monitores: {0}; comandos aceptados: {1}",
            found, succeeded);
    }

    public static int ReadBrightness() {
        int result = -1;

        MonitorEnum callback = delegate(
            IntPtr h, IntPtr dc, IntPtr rect, IntPtr data) {

            uint count = 0;

            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(h, out count)
                || count == 0)
                return true;

            PhysicalMonitor[] monitors = new PhysicalMonitor[count];

            if (!GetPhysicalMonitorsFromHMONITOR(h, count, monitors))
                return true;

            try {
                foreach (PhysicalMonitor m in monitors) {
                    byte type;
                    uint current, maximum;

                    if (GetVCPFeatureAndVCPFeatureReply(
                        m.handle, 0x10, out type,
                        out current, out maximum) && maximum > 0) {
                        result = (int)Math.Round(
                            current * 100.0 / maximum);
                        return false;
                    }
                }
            }
            finally {
                DestroyPhysicalMonitors(count, monitors);
            }

            return true;
        };

        EnumDisplayMonitors(
            IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);

        return result;
    }
}
'@

# --------------------------------------------------
# Formulario: se crea oculto
# --------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Monitor Brightness"
$form.Size = New-Object System.Drawing.Size(310, 115)
$form.FormBorderStyle = 'FixedToolWindow'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = 'Manual'

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(12, 10)
$label.Size = New-Object System.Drawing.Size(270, 20)
$label.Text = "Brillo"
$form.Controls.Add($label)

$slider = New-Object System.Windows.Forms.TrackBar
$slider.Location = New-Object System.Drawing.Point(8, 32)
$slider.Size = New-Object System.Drawing.Size(280, 42)
$slider.Minimum = 0
$slider.Maximum = 100
$slider.TickFrequency = 10
$slider.SmallChange = 1
$slider.LargeChange = 10

$current = [TrayDdc]::ReadBrightness()

if ($current -ge 0) {
    $slider.Value = [Math]::Max(0, [Math]::Min(100, $current))
} else {
    $slider.Value = 100
}

$label.Text = "Brillo: $($slider.Value)%"
$form.Controls.Add($slider)

$status = New-Object System.Windows.Forms.ToolTip
$status.SetToolTip($slider, "Brillo DDC/CI")

$script:updatingSlider = $false

$slider.Add_ValueChanged({
    $label.Text = "Brillo: $($slider.Value)%"

    if (-not $script:updatingSlider) {
        try {
            $result = [TrayDdc]::SetBrightness($slider.Value)
            $status.SetToolTip($slider, $result)
        } catch {
            $status.SetToolTip($slider, $_.Exception.Message)
        }
    }
})

# --------------------------------------------------
# Mostrar el deslizador solo desde el menú contextual
# --------------------------------------------------

$showWindow = {
    $script:updatingSlider = $true

    try {
        $current = [TrayDdc]::ReadBrightness()

        if ($current -ge 0) {
            $slider.Value = [Math]::Max(
                0, [Math]::Min(100, $current))
        }
    } finally {
        $script:updatingSlider = $false
    }

    if (-not $form.Visible) {
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

        $form.Location = New-Object System.Drawing.Point(
            ($area.Right - $form.Width - 8),
            ($area.Bottom - $form.Height - 8)
        )

        $form.Show()
    }

    $form.Activate()
}

# Ocultar el deslizador al perder el foco
$form.Add_Deactivate({
    $form.Hide()
})

# --------------------------------------------------
# Menú contextual
# --------------------------------------------------

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$openItem = $menu.Items.Add("Ajustar brillo")
$openItem.Add_Click($showWindow)

$menu.Items.Add("-") | Out-Null

foreach ($level in @(25, 50, 75, 100)) {
    $item = $menu.Items.Add("$level%")
    $item.Tag = $level

    $item.Add_Click({
        $value = [int]$this.Tag

        try {
            $result = [TrayDdc]::SetBrightness($value)

            $script:updatingSlider = $true
            try {
                $slider.Value = $value
                $label.Text = "Brillo: $value%"
            } finally {
                $script:updatingSlider = $false
            }

            $status.SetToolTip($slider, $result)
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Error al cambiar el brillo"
            )
        }
    })
}

$menu.Items.Add("-") | Out-Null
$exitItem = $menu.Items.Add("Salir")

# --------------------------------------------------
# Icono de bandeja: Asterisk
# --------------------------------------------------

$tray = New-Object System.Windows.Forms.NotifyIcon

# Usar explícitamente el icono Asterisk de Windows
$iconPath = Join-Path $PSScriptRoot "ExternalMonitor-BrightnessControl.ico"
$tray.Icon = New-Object System.Drawing.Icon($iconPath)
$tray.Text = "Monitor Brightness"
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

# ApplicationContext mantiene la aplicación activa
# sin mostrar el formulario al arrancar
$context = New-Object System.Windows.Forms.ApplicationContext

# Crear el handle del formulario para BeginInvoke
$null = $form.Handle

# --------------------------------------------------
# Cierre de la aplicación
# --------------------------------------------------

$exitHandler = {
    $context.ExitThread()
}

$exitItem.Add_Click($exitHandler)

# Ctrl+C desde la consola
$cancelHandler = [ConsoleCancelEventHandler] {
    param($sender, $e)

    $e.Cancel = $true

    try {
        $null = $form.BeginInvoke([Action]{
            $context.ExitThread()
        })
    } catch {
        # La aplicación ya se está cerrando
    }
}

[Console]::add_CancelKeyPress($cancelHandler)

try {
    [System.Windows.Forms.Application]::Run($context)
}
finally {
    [Console]::remove_CancelKeyPress($cancelHandler)

    $tray.Visible = $false
    $tray.Dispose()

    $form.Dispose()
    $status.Dispose()
    $menu.Dispose()
}
