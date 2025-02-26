using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Reflection.PortableExecutable;
using System.Text;
using System.Threading.Tasks;
using ZXing;
using ZXing.Common;
using ZXing.QrCode;
using ZXing.Windows.Compatibility;

namespace Fededim.Utilities
{
    public class BarCodeExtractor
    {
        public BarcodeReader Reader { get; protected set; }
        protected ILogger<BarCodeExtractor> Logger { get; set; }


        public BarCodeExtractor(ILogger<BarCodeExtractor> logger = null)
        {
            Reader = new BarcodeReader();
            Reader.AutoRotate = true;
            Reader.Options.TryInverted = true;
            Reader.Options.TryHarder = true;

            Logger = logger;
        }


        public BarCodeExtractor(DecodingOptions options)
        {
            Reader = new BarcodeReader() { Options = options };
        }


        public Result[] ExtractQrCodes(string imageFile)
        {
            Reader.Options.PossibleFormats = new List<ZXing.BarcodeFormat>() { ZXing.BarcodeFormat.QR_CODE };

            // load a bitmap
            var barcodeBitmap = (Bitmap)Image.FromFile(imageFile);

            // detect and decode all the qr codes inside the bitmap
            var qrCodes = Reader.DecodeMultiple(barcodeBitmap);

            Logger?.LogInformation($"File {imageFile} extracted {qrCodes.Length} QR codes...");

            return qrCodes;
        }
    }
}
