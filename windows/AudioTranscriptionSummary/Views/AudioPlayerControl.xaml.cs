using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AudioTranscriptionSummary.Views;

public sealed partial class AudioPlayerControl : UserControl
{
    public AudioPlayerControl()
    {
        this.InitializeComponent();
    }

    private void OnPlayPause(object sender, RoutedEventArgs e)
    {
        // Playback is handled inline in MainPage via MainViewModel
    }
}
