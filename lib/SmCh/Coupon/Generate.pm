package SmCh::Coupon::Generate;
use strict;
use warnings;

use base qw( Exporter );
use Image::Magick;
use Barcode::Code128;

our @EXPORT_OK = qw(
    generateCouponNumber
    generateCouponImg
);
my $oy_code = 150;    # начало ШК по Y
my $h_code  = 180;    # высота ШК
my $w_code  = 420;    # ширина ШК
my $h_text  = 30;     # высота текста ШК

################################################################################
sub generateCouponNumber
{
    my $length = shift;

# Простой способ получить последовательность цифр
# При этом больше 10**18 нельзя
    my $answer = int 10**18 * rand;

    while ( length( $answer ) < $length )
    {
        $answer .= int 10**18 * rand;
    }
    $answer = substr( $answer, 0, $length );
    return $answer;
}
################################################################################
sub generateCouponImg
{
    my $img    = shift;
    my $coupon = shift;

    my %arg = @_;

    my $baseIM = new Image::Magick;

    my $err = $baseIM->BlobToImage( $img );
    if ($err) {
        print "$err\n";
        return;
    }
    my ( $widthBaseIM, $heightBaseIM ) =
        $baseIM->Get( 'base-columns', 'base-rows' );

### затираем белым цветом в макете область для ШК
    my $whiteIM = new Image::Magick;
    $whiteIM->Set( size => $w_code . 'x' . $h_code );
    $whiteIM->ReadImage( 'xc:#fff' );

    $baseIM->Composite(
        image   => $whiteIM,
        x       => 0,
        y       => $oy_code,
        compose => 'Replace',
    );

#### создаем PNG с ШК в формате code128
    my $code128    = new Barcode::Code128();
    my $barcodePng = $code128->png(
        $coupon,
        {
            border    => 0,
            show_text => 0,
            height    => $h_code,
            padding   => 0,
            scale     => 2
        }
    );
    my $barcodeIM = new Image::Magick;
    $barcodeIM->BlobToImage( $barcodePng );
    my ( $widthBarcodeIM, $heightBarcodeIM ) =
        $barcodeIM->Get( 'base-columns', 'base-rows' );

### создаем область с белым фоном для текстового отображения ШК
    my $couponTextIM = new Image::Magick;
    $couponTextIM->Set( size => $w_code . 'x' . $h_text );
    $couponTextIM->ReadImage( 'xc:#fff' );
    $couponTextIM->Annotate(
        text      => $coupon,
        pointsize => 24,
        fill      => '#000',
        gravity   => 'Center',
    );
### наносим на ШК его текстовое представление
    $barcodeIM->Composite(
        image   => $couponTextIM,
        gravity => 'South',
        compose => 'Replace',
    );

### наносим ШК на макет
    $baseIM->Composite(
        image   => $barcodeIM,
        x       => ( ( $widthBaseIM - $widthBarcodeIM ) / 2 ),
        y       => $oy_code,
        compose => 'Replace',
    );

### делаем монохром, 2-цвета
    $baseIM->Quantize(
        colorspace => 'Gray',
        colors     => 2,
    );

    return $baseIM->ImageToBlob;
}
################################################################################
1;
