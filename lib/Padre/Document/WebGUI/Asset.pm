package Padre::Document::WebGUI::Asset;

# ABSTRACT: Padre::Document subclass representing a WebGUI Asset

use strict;
use warnings;

use Carp;
use Padre::Logger;
use Padre::Document ();

our @ISA = 'Padre::Document';

use Class::XSAccessor getters => {
    asset => 'asset',
    url   => 'url',
};

=method asset

Accessor

=method url

Accessor

=method basename

File-faking accessor

=cut

sub basename { $_[0]->filename }

=method dirname

File-faking accessor

=cut

sub dirname { $_[0]->basename }

=method time_on_file

File-faking accessor

=cut

sub time_on_file { $_[0]->asset->{revisionDate} }

=method load_file

File-faking accessor

=cut

sub load_file { $_[0]->load_asset }

=method is_new

File-faking accessor

=cut

sub is_new { 0 }

=method lexer

Override this to change the highlighter/lexer

=cut

sub lexer { Padre::MimeTypes->get_lexer('text/html') }

=method load_asset

=cut

sub load_asset {
    my ( $self, $assetId, $url ) = @_;

    TRACE( "Loading asset $assetId from $url with mimetype " . $self->get_mimetype ) if DEBUG;

    # TODO: Investigate whether we should actually subclass Padre::File rather than faking it
    #    $self->{file} = {};

    $self->{url} = $url;

    # Create a user agent object
    use LWP::UserAgent;
    my $ua  = LWP::UserAgent->new;
    my $get = "$url?op=padre&func=edit&assetId=$assetId";
    TRACE("GET: $get") if DEBUG;
    my $response = $ua->get($get);
    unless ( $response->header('Padre-Plugin-WebGUI') ) {
        my $error = "The server does not appear to have the Padre::Plugin::WebGUI content handler installed";
        $self->set_errstr($error);
        $self->editor->main->error($error);
        return;
    }
    if ( !$response->is_success ) {
        my $error = "The server said:\n" . $response->status_line;
        $self->set_errstr($error);
        $self->editor->main->error($error);
        return;
    }

    return $self->process_response( $response->content );
}

=method save_file

Override Padre::Document::save_file

=cut

sub save_file {
    my $self = shift;

    my $asset = $self->asset;
    return unless $asset;
    my $url = $self->url;

    # Two saves in the same second will cause asset->addRevision to explode
    return 1 if $self->timestamp && $self->timestamp == time;

    TRACE("Saving asset $asset->{assetId}") if DEBUG;

    # Put editor text back into asset hash
    $self->set_asset_content;

    # Create a user agent object
    use LWP::UserAgent;
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->post(
        $url,
        {
            op      => 'padre',
            func    => 'save',
            assetId => $asset->{assetId},
            props   => encode_json($asset),
        }
    );
    unless ( $response->header('Padre-Plugin-WebGUI') ) {
        my $error = "The server does not appear to have the Padre::Plugin::WebGUI content handler installed";
        $self->set_errstr($error);
        $self->editor->main->error($error);
        return;
    }
    if ( !$response->is_success ) {
        $self->set_errstr( "The server said:\n" . $response->status_line );
    require utf8;
        return;
    }

    return $self->process_response( $response->content );
}

=method process_response

=cut

sub process_response {
    my $self    = shift;
    my $content = shift;

    # TRACE($content) if DEBUG;

    use JSON;
    my $asset = eval { decode_json($content) };
    if ($@) {
        TRACE($@) if DEBUG;
        warn $@;
        my $error = "The server sent an invalid response, please try again (and check the logs)";
        $self->set_errstr($error);
        $self->editor->main->error($error);
        return;
    }

    $self->{asset}      = $asset;
    $self->{_timestamp} = $self->time_on_file;

    # Set a fake filename, so that we the file isn't considered 'new'
    #$self->{filename} = "[$asset->{name}] $asset->{menuTitle}"; # asset name not needed now that icon shown
    $self->{filename} = $asset->{menuTitle};

    $self->render;

    return 1;
}

=method get_asset_content

You can override this to edit something other than the generic 'content' field

=cut

sub get_asset_content {
    my $self = shift;
    return $self->asset->{content};
}

=method set_asset_content

This is paired with L<get_asset_content> - it gets called to store the editor text
back into the appropriate asset field prior to sending hash to server

=cut

sub set_asset_content {
    my $self = shift;
    $self->asset->{content} = $self->text_get;
}

=method render

You can override this to do something entirely different with the asset

=cut

sub render {
    my $self  = shift;
    my $asset = $self->asset;

    # Set text (a la Padre::Document::load_file)
    my $text = $self->get_asset_content || q{};

    require Padre::Locale;
    $self->{encoding} = Padre::Locale::encoding_from_string($text);
    unless ( utf8::is_utf8( $text ) ) { 
        my $decoded = eval {  Encode::decode( $self->{encoding}, $text ) }; 
        if ( $@ ) {
            my $error = "File has bad characters. I think it is in $self->{ encoding }, but it is not entirely
            so.";
            $self->set_errstr( $error );
            $self->editor->main->error( $error );
        }
        else {
            $text = $decoded;
        }
    }
    $self->text_set($text);
    $self->{original_content} = $self->text_get;
    $self->colourize;
}

=method TRACE

=cut

1;
