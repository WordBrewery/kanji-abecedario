port module Main exposing (..)

import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode


main : Program Never Model Msg
main =
    Html.program { init = init, view = view, update = update, subscriptions = subscriptions }



-- MODEL


type alias Model =
    { err : String, target : String }


init : ( Model, Cmd Msg )
init =
    ( Model "" "冫", askFirstNoDeps )



-- UPDATE


type Msg
    = Login
    | AskFirstNoDeps
    | FirstNoDeps (Result Http.Error String)


port login : String -> Cmd msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Login ->
            ( model, login "doesntmatter" )

        AskFirstNoDeps ->
            ( model, askFirstNoDeps )

        FirstNoDeps (Ok target) ->
            ( { model | target = target }, Cmd.none )

        FirstNoDeps (Err err) ->
            ( { model | err = (toString err) }, Cmd.none )


firstNoDepsDecoder : Decode.Decoder String
firstNoDepsDecoder =
    Decode.at [ "0", "target" ] Decode.string


askFirstNoDeps : Cmd Msg
askFirstNoDeps =
    Http.send FirstNoDeps (Http.get "http://localhost:3000/firstNoDeps" firstNoDepsDecoder)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Login ] [ text "Login from Elm" ]
        , button [ onClick AskFirstNoDeps ] [ text "Ask for first target" ]
        , div [] [ text (toString model) ]
        , text model.target
        , div [] [ text model.err ]
        ]
