# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
package Lstu::Controller::Admin;
use Mojo::Base 'Mojolicious::Controller';
use Digest::SHA qw(sha256_hex);
use Lstu::DB::URL;
use Lstu::DB::Ban;
use Lstu::DB::Session;

sub login {
    my $c    = shift;
    my $pwd  = $c->param('adminpwd');
    my $act  = $c->param('action');

    $c->cleaning;

    my $ip = $c->ip;

    my $banned = Lstu::DB::Ban->new(
        app    => $c,
        ip     => $ip
    )->is_banned($c->config('ban_min_strike'));
    if (defined $banned) {
        my $penalty = 3600;
        if ($banned->strike >= 2 * $c->config('ban_min_strike')) {
            $penalty = 3600 * 24 * 30; # 30 days of banishing
        }
        $banned->increment_ban_delay($penalty);

        $c->flash('msg'    => $c->l('Too many bad passwords. You\'re banned.'));
        $c->flash('banned' => 1);
        $c->redirect_to('stats');
    } else {
        if (
            (defined($c->config('adminpwd')) && defined($pwd) && $pwd eq $c->config('adminpwd')) ||
            (defined($c->config('hashed_adminpwd')) && defined($pwd) && sha256_hex($pwd) eq $c->config('hashed_adminpwd'))
           ) {
            my $token = $c->shortener(32);

            Lstu::DB::Session->new(
                app    => $c,
                token  => $token,
                until  => time + 3600
            )->write;

            $c->session('token' => $token);
            $c->respond_to(
                json => sub {
                    my $c = shift;
                    $c->render(
                        json => {
                            success => Mojo::JSON->true,
                            msg     => $c->l('You have been successfully logged in.')
                        }
                    );
                },
                any => sub {
                    my $c = shift;
                    $c->redirect_to('stats');
                }
            );
        } elsif (defined($act) && $act eq 'logout') {
            Lstu::DB::Session->new(
                app    => $c,
                token  => $c->session('token')
            )->remove;
            delete $c->session->{token};
            $c->respond_to(
                json => sub {
                    my $c = shift;
                    $c->render(
                        json => {
                            success => Mojo::JSON->true,
                            msg     => $c->l('You have been successfully logged out.')
                        }
                    );
                },
                any => sub {
                    shift->redirect_to('stats');
                }
            );
        } else {
            Lstu::DB::Ban->new(
                app    => $c,
                ip     => $ip
            )->increment_ban_delay(3600);

            my $msg = $c->l('Bad password');
            $c->respond_to(
                json => sub {
                    my $c = shift;
                    $c->render(
                        json => {
                            success => Mojo::JSON->false,
                            msg     => $msg
                        }
                    );
                },
                any => sub {
                    my $c = shift;
                    $c->flash('msg' => $msg);
                    $c->redirect_to('stats');
                }
            );
        }
    }
}

sub delete {
    my $c     = shift;
    my $short = $c->param('short');

    my $db_session = Lstu::DB::Session->new(
        app    => $c,
        token  => $c->session('token')
    );
    if (defined($c->session('token')) && $db_session->is_valid) {
        my $db_url = Lstu::DB::URL->new(
            app    => $c,
            short  => $short
        );
        if ($db_url->url) {
            my $deleted = $db_url->remove;
            $c->respond_to(
                json => { json => { success => Mojo::JSON->true, deleted => $deleted } },
                any  => sub {
                    my $c = shift;
                    $c->redirect_to('stats');
                }
            );
        } else {
            my $msg = $c->l('The shortened URL %1 doesn\'t exist.', $c->url_for('/')->to_abs.$short);
            $c->respond_to(
                json => { json => { success => Mojo::JSON->false, msg => $msg } },
                any  => sub {
                    my $c = shift;
                    $c->flash('msg' => $msg);
                    $c->redirect_to('stats');
                }
            );
        }
    } else {
        $c->flash('msg' => $c->l('You\'re not authenticated as the admin'));
        $c->redirect_to('stats');
    }
}

1;
